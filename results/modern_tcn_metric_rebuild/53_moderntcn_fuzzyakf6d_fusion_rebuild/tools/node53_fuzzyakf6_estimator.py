from __future__ import annotations

import math
from dataclasses import dataclass
from typing import Any

import numpy as np


def nearest_psd(p: np.ndarray, floor: float = 1e-12) -> np.ndarray:
    p = 0.5 * (p + p.T)
    values, vectors = np.linalg.eigh(p)
    return (vectors * np.maximum(values, floor)) @ vectors.T


@dataclass
class FuzzyOutput:
    theta_imu: float
    theta_acc: float
    theta_pred: float
    accel_weight: float
    accel_norm: float
    innovation: float
    nis: float
    min_covariance_eigenvalue: float
    observer_valid: bool
    gyro_energy: float
    gyro_vibration_feature: float

    @property
    def valid(self) -> bool:
        return self.observer_valid


class FuzzyAKF6D:
    """Independent Node53 copy of frozen R2_06_FuzzyAKF6D."""

    def __init__(self, cfg: dict[str, Any]):
        self.c = cfg
        self.x = np.zeros(2, dtype=float)
        self.p = np.diag([math.radians(cfg["initial_pitch_std_deg"]) ** 2, cfg["initial_bias_std_rad_s"] ** 2])
        self.initialized = False
        self.gyro_energy = 0.0

    def update(self, packet: np.ndarray) -> FuzzyOutput:
        packet = np.asarray(packet, dtype=float).reshape(-1)
        if packet.size != 6 or not np.all(np.isfinite(packet)):
            raise ValueError("Expected six finite IMU channels [fx fy fz gx gy gz]")
        accel, gyro = packet[:3], packet[3:]
        accel_norm = float(np.linalg.norm(accel))
        theta_acc = math.atan2(float(accel[0]), float(accel[2]))
        if not self.initialized:
            self.x[0] = theta_acc
            self.initialized = True
        f = np.array([[1.0, -self.c["Ts"]], [0.0, 1.0]])
        xpred = np.array([self.x[0] + self.c["Ts"] * (gyro[1] - self.x[1]), self.x[1]])
        q = np.diag([(self.c["gyro_noise_std_rad_s"] * self.c["Ts"]) ** 2, (self.c["bias_rw_std_rad_s"] * self.c["Ts"]) ** 2])
        ppred = nearest_psd(f @ self.p @ f.T + q)
        innovation = math.atan2(math.sin(theta_acc - xpred[0]), math.cos(theta_acc - xpred[0]))
        self.gyro_energy = self.c["vibration_alpha"] * self.gyro_energy + (1.0 - self.c["vibration_alpha"]) * float(gyro @ gyro)
        norm_feature = min(1.0, abs(accel_norm - self.c["g"]) / (self.c["norm_full_scale_g"] * self.c["g"]))
        vibration_feature = min(1.0, math.sqrt(max(self.gyro_energy, 0.0)) / self.c["gyro_full_scale_rad_s"])
        innovation_feature = min(1.0, abs(innovation) / math.radians(self.c["innovation_full_scale_deg"]))
        risk = self.c["norm_weight"] * norm_feature + self.c["vibration_weight"] * vibration_feature + self.c["innovation_weight"] * innovation_feature
        r = math.radians(self.c["accel_pitch_std_deg"]) ** 2 * (1.0 + self.c["max_r_multiplier"] * min(1.0, risk))
        s = float(ppred[0, 0] + r)
        k = ppred[:, 0] / s
        self.x = xpred + k * innovation
        ikh = np.eye(2) - np.outer(k, np.array([1.0, 0.0]))
        self.p = nearest_psd(ikh @ ppred @ ikh.T + np.outer(k, k) * r)
        weight = 1.0 / (1.0 + self.c["max_r_multiplier"] * min(1.0, risk))
        nis = innovation * innovation / s
        mineig = float(np.min(np.linalg.eigvalsh(self.p)))
        valid = bool(np.all(np.isfinite(self.x)) and np.all(np.isfinite(self.p)) and mineig >= -1e-10)
        return FuzzyOutput(float(self.x[0]), theta_acc, float(xpred[0]), weight, accel_norm, innovation, nis, mineig, valid, float(self.gyro_energy), float(vibration_feature))


def replay(packet: np.ndarray, cfg: dict[str, Any]) -> dict[str, np.ndarray]:
    estimator = FuzzyAKF6D(cfg)
    outputs = [estimator.update(row) for row in np.asarray(packet, dtype=float)]
    names = ("theta_imu", "theta_acc", "theta_pred", "accel_weight", "accel_norm", "innovation", "nis", "min_covariance_eigenvalue", "observer_valid", "gyro_energy", "gyro_vibration_feature")
    return {name: np.asarray([getattr(item, name) for item in outputs]) for name in names}
