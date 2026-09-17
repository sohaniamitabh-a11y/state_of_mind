#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform float uTime;

out vec4 fragColor;

const vec3 kColorA = vec3(0.043, 0.055, 0.090);
const vec3 kColorB = vec3(0.078, 0.024, 0.110);
const vec3 kColorC = vec3(0.012, 0.086, 0.098);

float hash(vec2 p) {
  p = fract(p * vec2(123.34, 456.21));
  p += dot(p, p + 45.32);
  return fract(p.x * p.y);
}

float noise(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  float a = hash(i);
  float b = hash(i + vec2(1.0, 0.0));
  float c = hash(i + vec2(0.0, 1.0));
  float d = hash(i + vec2(1.0, 1.0));
  vec2 u = f * f * (3.0 - 2.0 * f);
  return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float grain(vec2 p) {
  return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453123);
}

void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;
  vec2 p = uv * vec2(uSize.x / uSize.y, 1.0);
  float t = uTime * 0.06;

  float n1 = noise(p * 2.4 + vec2(t, t * 0.6));
  float n2 = noise(p * 2.4 + vec2(-t * 0.8, t) + 17.0);
  float n3 = noise(p * 2.4 + vec2(t * 0.5, -t * 0.7) + 41.0);

  float sum = n1 + n2 + n3 + 1e-4;
  float w1 = n1 / sum;
  float w2 = n2 / sum;
  float w3 = n3 / sum;

  vec3 color = kColorA * w1 + kColorB * w2 + kColorC * w3;

  float g = grain(FlutterFragCoord().xy + fract(uTime) * 97.0) - 0.5;
  color += g * 0.025;

  fragColor = vec4(color, 1.0);
}
