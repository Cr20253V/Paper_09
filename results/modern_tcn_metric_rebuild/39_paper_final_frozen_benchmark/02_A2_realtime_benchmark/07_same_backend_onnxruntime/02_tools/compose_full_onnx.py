from __future__ import annotations

import copy
import csv
import hashlib
import json
from pathlib import Path

import numpy as np
import onnx
import onnxruntime as ort
from onnx import TensorProto, helper, numpy_helper
from scipy.io import loadmat

from a2ort_paths import (
    DERIVED,
    EXPECTED_PARENT_SHA,
    GRU_FEATURE_ONNX,
    GRU_FULL_ONNX,
    GRU_HEADS_MAT,
    ORT_ROOT,
    TCN_FEATURE_ONNX,
    TCN_FULL_ONNX,
    TCN_HEADS_MAT,
)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def add_initializer(graph: onnx.GraphProto, name: str, value: np.ndarray) -> str:
    graph.initializer.append(numpy_helper.from_array(np.asarray(value), name=name))
    return name


def feature_layout(path: Path) -> tuple[str, str, tuple[int, ...], int, int]:
    opts = ort.SessionOptions()
    opts.intra_op_num_threads = 1
    opts.inter_op_num_threads = 1
    opts.execution_mode = ort.ExecutionMode.ORT_SEQUENTIAL
    sess = ort.InferenceSession(str(path), sess_options=opts, providers=["CPUExecutionProvider"])
    inp = sess.get_inputs()[0]
    # MATLAB sequence export uses [time,batch,feature]. The frozen authority
    # inference is [time=1,batch=128,feature=22], despite presenting one
    # logical 128-sample window to the public predictor API.
    shape = tuple(1 if not isinstance(dim, int) else dim for dim in inp.shape)
    if len(shape) != 3:
        raise RuntimeError(f"Expected rank-3 MATLAB feature input, got {inp.shape}")
    out = sess.run(None, {inp.name: np.zeros(shape, dtype=np.float32)})[0]
    if out.ndim != 3 or 96 not in out.shape or 128 not in out.shape or 1 not in out.shape:
        raise RuntimeError(f"Unexpected feature output shape for {path.name}: {out.shape}")
    channel_axis = out.shape.index(96)
    time_axis = out.shape.index(128)
    return inp.name, sess.get_outputs()[0].name, tuple(out.shape), channel_axis, time_axis


def make_reduce(op_type: str, name: str, x: str, y: str, axis: int, keepdims: int = 0):
    return helper.make_node(op_type, [x], [y], name=name, axes=[axis], keepdims=keepdims)


def compose(method: str, feature_path: Path, heads_path: Path, output_path: Path) -> dict[str, object]:
    if output_path.exists():
        raise FileExistsError(f"Refusing to overwrite derived full model: {output_path}")
    old_input, feature_output, feature_shape, channel_axis, time_axis = feature_layout(feature_path)
    model = onnx.load(feature_path)
    graph = model.graph
    if len(graph.input) != 1 or len(graph.output) != 1:
        raise RuntimeError("Expected one feature input and one feature output")

    internal_input = "a2ort_feature_input_tbf"
    for node in graph.node:
        for i, value in enumerate(node.input):
            if value == old_input:
                node.input[i] = internal_input
    del graph.input[:]
    graph.input.extend(
        [helper.make_tensor_value_info("input_window", TensorProto.FLOAT, [1, 128, 22])]
    )
    # Numerically, the public [1,128,22] tensor is already the exported
    # [time=1,batch=128,feature=22] shape. Identity documents this boundary.
    identity = helper.make_node(
        "Identity", ["input_window"], [internal_input], name="a2ort_authority_layout_identity"
    )
    graph.node.insert(0, identity)

    old_output_info = copy.deepcopy(graph.output[0])
    graph.value_info.append(old_output_info)
    del graph.output[:]

    payload = loadmat(heads_path, simplify_cells=True)
    heads = payload["heads"]
    cfg = payload["cfg"]
    expected_pooling = "last_mean_max_inputstats" if method == "tcn_22d" else "last_mean_inputstats"
    if str(cfg["head_pooling"]) != expected_pooling:
        raise RuntimeError(f"Unexpected {method} pooling: {cfg['head_pooling']}")
    if str(cfg["turn_head_source"]) != "inputstats" or str(cfg["turn_head_type"]) != "mlp":
        raise RuntimeError(f"Unexpected {method} turn-head contract")

    idx_last = add_initializer(graph, "a2ort_idx_last", np.array(-1, dtype=np.int64))
    squeeze_time_axes = add_initializer(graph, "a2ort_squeeze_time_axes", np.array([1], dtype=np.int64))
    epsilon = add_initializer(graph, "a2ort_std_epsilon", np.array(1e-8, dtype=np.float32))

    nodes = [
        helper.make_node("Gather", ["input_window", idx_last], ["a2ort_x_last"], name="a2ort_x_last", axis=1),
        make_reduce("ReduceMean", "a2ort_x_mean_keep", "input_window", "a2ort_x_mean_keep", 1, 1),
        helper.make_node("Squeeze", ["a2ort_x_mean_keep", squeeze_time_axes], ["a2ort_x_mean"], name="a2ort_x_mean"),
        helper.make_node("Sub", ["input_window", "a2ort_x_mean_keep"], ["a2ort_x_centered"], name="a2ort_x_centered"),
        helper.make_node("Mul", ["a2ort_x_centered", "a2ort_x_centered"], ["a2ort_x_sq"], name="a2ort_x_sq"),
        make_reduce("ReduceMean", "a2ort_x_var", "a2ort_x_sq", "a2ort_x_var", 1, 0),
        helper.make_node("Add", ["a2ort_x_var", epsilon], ["a2ort_x_var_eps"], name="a2ort_x_var_eps"),
        helper.make_node("Sqrt", ["a2ort_x_var_eps"], ["a2ort_x_std"], name="a2ort_x_std"),
        make_reduce("ReduceMax", "a2ort_x_max", "input_window", "a2ort_x_max", 1, 0),
        make_reduce("ReduceMin", "a2ort_x_min", "input_window", "a2ort_x_min", 1, 0),
        helper.make_node(
            "Concat",
            ["a2ort_x_last", "a2ort_x_mean", "a2ort_x_std", "a2ort_x_max", "a2ort_x_min"],
            ["a2ort_inputstats"],
            name="a2ort_inputstats",
            axis=1,
        ),
        helper.make_node("Gather", [feature_output, idx_last], ["a2ort_z_last"], name="a2ort_z_last", axis=time_axis),
        make_reduce("ReduceMean", "a2ort_z_mean", feature_output, "a2ort_z_mean", time_axis, 0),
    ]
    readout_inputs = ["a2ort_z_last", "a2ort_z_mean"]
    if method == "tcn_22d":
        nodes.append(make_reduce("ReduceMax", "a2ort_z_max", feature_output, "a2ort_z_max", time_axis, 0))
        readout_inputs.append("a2ort_z_max")
    readout_inputs.append("a2ort_inputstats")
    nodes.append(helper.make_node("Concat", readout_inputs, ["a2ort_readout"], name="a2ort_readout", axis=1))

    normalized_heads = {
        "main_W": np.asarray(heads["main_W"], dtype=np.float32).reshape(3, -1),
        "main_b": np.asarray(heads["main_b"], dtype=np.float32).reshape(-1),
        "theta_W": np.asarray(heads["theta_W"], dtype=np.float32).reshape(1, -1),
        "theta_b": np.asarray(heads["theta_b"], dtype=np.float32).reshape(-1),
        "turn_W1": np.asarray(heads["turn_W1"], dtype=np.float32).reshape(64, -1),
        "turn_b1": np.asarray(heads["turn_b1"], dtype=np.float32).reshape(-1),
        "turn_W2": np.asarray(heads["turn_W2"], dtype=np.float32).reshape(3, -1),
        "turn_b2": np.asarray(heads["turn_b2"], dtype=np.float32).reshape(-1),
    }
    for name, value in normalized_heads.items():
        add_initializer(graph, f"a2ort_{name}", value)
    nodes.extend(
        [
            helper.make_node("Gemm", ["a2ort_readout", "a2ort_main_W", "a2ort_main_b"], ["logits_main"], name="a2ort_main_head", transB=1),
            helper.make_node("Gemm", ["a2ort_readout", "a2ort_theta_W", "a2ort_theta_b"], ["theta_hat"], name="a2ort_theta_head", transB=1),
            helper.make_node("Gemm", ["a2ort_inputstats", "a2ort_turn_W1", "a2ort_turn_b1"], ["a2ort_turn_hidden_pre"], name="a2ort_turn_hidden", transB=1),
            helper.make_node("Relu", ["a2ort_turn_hidden_pre"], ["a2ort_turn_hidden"], name="a2ort_turn_relu"),
            helper.make_node("Gemm", ["a2ort_turn_hidden", "a2ort_turn_W2", "a2ort_turn_b2"], ["logits_turn"], name="a2ort_turn_head", transB=1),
        ]
    )
    graph.node.extend(nodes)
    graph.output.extend(
        [
            helper.make_tensor_value_info("logits_main", TensorProto.FLOAT, [1, 3]),
            helper.make_tensor_value_info("logits_turn", TensorProto.FLOAT, [1, 3]),
            helper.make_tensor_value_info("theta_hat", TensorProto.FLOAT, [1, 1]),
        ]
    )
    model.doc_string = (
        f"A2 unified-ORT derivative of frozen A1 {method} seed42; "
        "MATLAB feature_net export plus immutable readout and heads."
    )
    onnx.checker.check_model(model)
    onnx.save(model, output_path)
    session = ort.InferenceSession(str(output_path), providers=["CPUExecutionProvider"])
    result = session.run(None, {"input_window": np.zeros((1, 128, 22), dtype=np.float32)})
    if [tuple(x.shape) for x in result] != [(1, 3), (1, 3), (1, 1)]:
        raise RuntimeError(f"Unexpected composed outputs for {method}")
    return {
        "method_id": method,
        "feature_output_shape": list(feature_shape),
        "feature_channel_axis": channel_axis,
        "feature_time_axis": time_axis,
        "feature_onnx": str(feature_path.resolve()),
        "feature_sha256": sha256(feature_path),
        "heads_file": str(heads_path.resolve()),
        "heads_sha256": sha256(heads_path),
        "full_onnx": str(output_path.resolve()),
        "full_sha256": sha256(output_path),
        "parent_authority_sha256": EXPECTED_PARENT_SHA[method],
    }


def main() -> None:
    specs = [
        ("tcn_22d", TCN_FEATURE_ONNX, TCN_HEADS_MAT, TCN_FULL_ONNX),
        ("gru_22d", GRU_FEATURE_ONNX, GRU_HEADS_MAT, GRU_FULL_ONNX),
    ]
    records = []
    for method, feature, heads, full in specs:
        if full.exists():
            sess = ort.InferenceSession(str(full), providers=["CPUExecutionProvider"])
            outputs = sess.run(None, {sess.get_inputs()[0].name: np.zeros((1, 128, 22), np.float32)})
            if [tuple(x.shape) for x in outputs] != [(1, 3), (1, 3), (1, 1)]:
                raise RuntimeError(f"Existing derived model is invalid: {full}")
            _, _, feature_shape, channel_axis, time_axis = feature_layout(feature)
            records.append({
                "method_id": method,
                "feature_output_shape": list(feature_shape),
                "feature_channel_axis": channel_axis,
                "feature_time_axis": time_axis,
                "feature_onnx": str(feature.resolve()),
                "feature_sha256": sha256(feature),
                "heads_file": str(heads.resolve()),
                "heads_sha256": sha256(heads),
                "full_onnx": str(full.resolve()),
                "full_sha256": sha256(full),
                "parent_authority_sha256": EXPECTED_PARENT_SHA[method],
            })
        else:
            records.append(compose(method, feature, heads, full))
    (DERIVED / "composition_manifest.json").write_text(
        json.dumps(records, indent=2, ensure_ascii=False), encoding="utf-8"
    )
    with (ORT_ROOT / "01_inventory/derived_model_registry.csv").open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(records[0]))
        writer.writeheader()
        writer.writerows(records)
    print("Complete TCN and GRU ONNX predictors composed.")


if __name__ == "__main__":
    main()
