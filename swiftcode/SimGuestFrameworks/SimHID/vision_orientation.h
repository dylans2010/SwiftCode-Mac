#ifndef SIMHID_VISION_ORIENTATION_H
#define SIMHID_VISION_ORIENTATION_H

#include <stdint.h>

typedef void *(*QuaternionOrientationCreator)(const void *allocator, uint64_t timeStamp, double w, double x, double y, double z,
                                              uint32_t options);

static inline void vision_normalize_quaternion(const double q[4], double out[4]) {
    double n = q[0] * q[0] + q[1] * q[1] + q[2] * q[2] + q[3] * q[3];
    if (!(n > 1e-12) || n != n || n > 1e12) {
        out[0] = 1; out[1] = out[2] = out[3] = 0;
        return;
    }
    double r = n > 1 ? n : 1;
    for (int i = 0; i < 60; i++) r = 0.5 * (r + n / r);
    for (int i = 0; i < 4; i++) out[i] = q[i] / r;
}

static inline void *vision_quaternion_event(QuaternionOrientationCreator create, uint64_t ts, const double q[4]) {
    if (!create) return 0;
    double u[4];
    vision_normalize_quaternion(q, u);
    return create(0, ts, u[0], u[1], u[2], u[3], 0);
}

#endif
