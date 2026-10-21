// Common scene definitions
enum ShapeType {
    Circle,
    Polyline,
    QuadraticBezier
};

struct Shape {
    ShapeType type;
    // Index the shape into the type-specific arrays
    // (circles, polylines, or quadratic_beziers)
    int index;

    bool use_fill;
    float4 fill_rgba;
    bool use_stroke;
    float4 stroke_rgba;
    float stroke_width;
    // Maps screen/world-space positions to the shape's object space.
    float3x3 world_to_obj;
};

struct Circle {
    float2 center;
    float radius;
};

struct Polyline {
    int pts_begin;
    int pts_end;
    bool closed;
};

struct QuadraticBezier {
    int pts_begin;
    int pts_end;
    bool closed;
};

static const float PI = 3.14159265358979323846;

// Polynomial solvers
// Return true if a root is found.
// The two real roots are stored in t
bool solve_quadratic(float a, float b, float c,
                     out float2 t) {
    // From https://github.com/mmp/pbrt-v4/blob/master/src/pbrt/util/math.h#L613
    if (a == 0) {
        if (b == 0) {
            t = float2(0.0, 0.0);
            return false;
        }
        t = float2(-c / b, -c / b);
        return true;
    }

    float discrim = b * b - 4 * a * c;
    if (discrim < 0) {
        t = float2(0, 0);
        return false;
    }
    float root_discrim = sqrt(discrim);

    float q;
    if (b < 0) {
        q = -0.5f * (b - root_discrim);
    } else {
        q = -0.5f * (b + root_discrim);
    }
    t.x = q / a;
    t.y = c / q;
    return true;
}

// Returns real candidate roots needed for finding extrema.
// Repeated roots may be omitted.
int solve_cubic(float a, float b, float c, float d, out float3 t) {
    if (abs(a) < 1e-6) {
        if (solve_quadratic(b, c, d, t.xy)) {
            return 2;
        } else {
            return 0;
        }
    }
    // normalize cubic equation
    b /= a;
    c /= a;
    d /= a;
    float Q = (b * b - 3 * c) / 9.0;
    float R = (2 * b * b * b - 9 * b * c + 27 * d) / 54.0;
    if (R * R < Q * Q * Q) {
        // 3 real roots
        float theta = acos(R / sqrt(Q * Q * Q));
        t.x = -2.0 * sqrt(Q) * cos(theta / 3.0) - b / 3.0;
        t.y = -2.0 * sqrt(Q) * cos((theta - 2.0 * PI) / 3.0) - b / 3.0;
        t.z = -2.0 * sqrt(Q) * cos((theta + 2.0 * PI) / 3.0) - b / 3.0;
        return 3;
    } else {
        float A = R > 0 ? -pow(R + sqrt(R * R - Q * Q * Q), 1.0/3.0):
                           pow(-R + sqrt(R * R - Q * Q * Q), 1.0/3.0);
        float B = abs(A) > 1e-6 ? Q / A : 0.0;
        t.x = (A + B) - b / 3.0;
        return 1;
    }
}

// Solutions below
bool point_in_polyline_fill(StructuredBuffer<float2> points,
                            int begin, int end,
                            float2 pt) {
    // the code implicitly assumes that the polyline is closed
    // shoot a ray from "pt" towards right
    // intersect the ray with all lines
    // we count the "winding number" for each intersection: 
    // if the line is going up, winding number +1
    // otherwise winding number -1
    // we then use the "non-zero rule" to determine
    // the result
    int winding_number = 0;
    for (int i = begin; i < end; i++) {
        float2 p0 = points[i];
        float2 p1 = points[(i + 1 == end) ? begin : i + 1];
        // the ray is pt + t * (1, 0)
        // the line is p0 + s * (p1 - p0)
        // expanding, we have two equations:
        // pt.x + t = p0.x + s * (p1.x - p0.x)
        // pt.y = p0.y + s * (p1.y - p0.y)
        // from the second equation, we know that
        float s = (pt.y - p0.y) / (p1.y - p0.y);
        // from the first equation, we know that
        float t = p0.x + s * (p1.x - p0.x) - pt.x;

        // Next we decide whether we are going upward/downward
        // and whether the point is between the two vertices
        // in the y direction
        // The <= and < are designed so that a shared vertex
        // is not double counted
        bool upward_inside = p0.y <= pt.y && pt.y < p1.y;
        bool downward_inside = p1.y <= pt.y && pt.y < p0.y;
        if (!upward_inside && !downward_inside) {
            continue;
        }

        if (t > 0) {
            if (upward_inside) {
                winding_number += 1;
            } else {
                winding_number -= 1;
            }
        }
    }
    // return abs(winding_number) % 2 == 1 // even-odd rule
    return winding_number != 0; // non-zero rule
}

bool point_in_polyline_stroke(StructuredBuffer<float2> points,
                              int begin, int end,
                              float2 pt,
                              float stroke_width,
                              bool is_closed) {
    float half_stroke_width = stroke_width / 2;
    // check the distance between the point and the line
    for (int i = begin; i < end; i++) {
        if (!is_closed && i == end - 1) {
            break;
        }
        float2 p0 = points[i];
        float2 p1 = points[(i + 1 == end) ? begin : i + 1];
        // project pt to the line
        float t = dot(pt - p0, p1 - p0) / dot(p1 - p0, p1 - p0);
        if (t >= 0 && t <= 1) {
            float2 p = p0 + t * (p1 - p0);
            if (length(p - pt) < half_stroke_width) {
                return true;
            }
        } else {
            // We use round corners for path joins and
            // flat for line caps
            bool check_p0 = is_closed || i != begin;
            bool check_p1 = is_closed || i != end - 2;
            // Check the two end points
            if (check_p0 && length(pt - p0) < half_stroke_width) {
                return true;
            }
            if (check_p1 && length(pt - p1) < half_stroke_width) {
                return true;
            }
        }
    }
    return false;
}

bool point_in_quadratic_bezier_fill(StructuredBuffer<float2> points,
                                    int begin, int end,
                                    float2 pt) {
    // the code implicitly assumes that the polyline is closed
    // shoot a ray from "pt" towards right
    // intersect the ray with all lines
    // we count the "winding number" for each intersection: 
    // if the line is going up, winding number +1
    // otherwise winding number -1
    // we then use the "non-zero rule" to determine
    // the result
    int winding_number = 0;
    for (int i = begin; i < end; i+=2) {
        float2 p0 = points[i];
        float2 p1 = points[i + 1];
        float2 p2 = points[(i + 2 == end) ? begin : i + 2];
        // the ray is pt + t * (1, 0)
        // the curve is C(s) = (1-s)^2 p0 + 2(1-s)s p1 + s^2p2
        // expanding, we have two equations:
        // pt.x + t = (1-s)^2 p0.x + 2(1-s)s p1.x + s^2p2.x
        // pt.y = (1-s)^2 p0.y + 2(1-s)s p1.y + s^2p2.y
        // from the second equation, we can solve for s
        float2 s;
        if (solve_quadratic(p0.y-2*p1.y+p2.y,
                            -2*p0.y+2*p1.y,
                            p0.y-pt.y,
                            s)) {
            for (int j = 0; j < 2; j++) {
                if (s[j] >= 0 && s[j] <= 1) {
                    // compute the tangent C'(s): if it's positive
                    // then we add the winding number
                    float tangent = 2*(p0.y-2*p1.y+p2.y)*s[j]+(-2*p0.y+2*p1.y);

                    // same thing as the polylines, except now
                    // s[j] gives us exactly where the point is
                    bool upward_inside =
                        tangent > 0 && s[j] >= 0 && s[j] < 1;
                    bool downward_inside =
                        tangent < 0 && s[j] > 0 && s[j] <= 1;

                    if (!upward_inside && !downward_inside) {
                        continue;
                    }

                    // Now we have s, we can solve for t
                    float t = (p0.x-2*p1.x+p2.x)*s[j]*s[j] +
                              (-2*p0.x+2*p1.x)*s[j] +
                              p0.x-pt.x;
                    if (t > 0) {
                        if (upward_inside) {
                            winding_number += 1;
                        } else if (tangent < 0) {
                            winding_number -= 1;
                        }
                    }
                }
            }
        }
    }
    // return abs(winding_number) % 2 == 1 // even-odd rule
    return winding_number != 0; // non-zero rule
}

float2 eval_quadratic_bezier(float t,
                             float2 p0,
                             float2 p1,
                             float2 p2) {
    float tt = 1 - t;
    return (tt*tt)*p0 + (2*tt*t)*p1 + (t*t)*p2;
};

float sum(float2 x) {
    return x.x + x.y;
}

bool point_in_quadratic_bezier_stroke(StructuredBuffer<float2> points,
                                      int begin, int end,
                                      float2 pt,
                                      float stroke_width,
                                      bool is_closed) {
    float r = stroke_width / 2;
    int curve_end = is_closed ? end : end - 2;
    for (int i = begin; i < curve_end; i+=2) {
        float2 p0 = points[i];
        float2 p1 = points[i + 1];
        float2 p2 = points[(i + 2 == end) ? begin : i + 2];

        // Test the two end points.
        // Our curves are flat ends, so we need to avoid this case:
        bool check_p0 = is_closed || i != begin;
        bool check_p2 = is_closed || i != end - 3;
        if (check_p0 && length(eval_quadratic_bezier(0.0, p0, p1, p2) - pt) < r) {
            return true;
        }
        if (check_p2 && length(eval_quadratic_bezier(1.0, p0, p1, p2) - pt) < r) {
            return true;
        }

        // The curve is (1-t)^2p0 + 2(1-t)tp1 + t^2p2
        // = (p0-2p1+p2)t^2+(-2p0+2p1)t+p0 = q
        // Want to solve (q - pt) dot q' = 0
        // q' = (p0-2p1+p2)t + (-p0+p1)
        // Expanding (p0-2p1+p2)^2 t^3 +
        //           3(p0-2p1+p2)(-p0+p1) t^2 +
        //           (2(-p0+p1)^2+(p0-2p1+p2)(p0-pt))t +
        //           (-p0+p1)(p0-pt) = 0
        float A = sum((p0-2*p1+p2)*(p0-2*p1+p2));
        float B = sum(3*(p0-2*p1+p2)*(-p0+p1));
        float C = sum(2*(-p0+p1)*(-p0+p1)+(p0-2*p1+p2)*(p0-pt));
        float D = sum((-p0+p1)*(p0-pt));
        float3 t;
        int num_sol = solve_cubic(A, B, C, D, t);
        for (int j = 0; j < num_sol; j++) {
            if (t[j] >= 0 && t[j] <= 1) {
                float2 p = eval_quadratic_bezier(t[j], p0, p1, p2);
                if (length(p - pt) < r) {
                    return true;
                }
            }
        }
    }
    return false;
}
