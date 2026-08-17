(function () {
var cv = document.querySelector("[data-identity-animation]");
if (!cv) return;
var g = cv.getContext("2d");
if (!g) return;
var STILL =
window.matchMedia &&
window.matchMedia("(prefers-reduced-motion: reduce)").matches;
var FPS = 30;
var TEETH = 9;
var W = 0,
H = 0;
var HALF = 0.5;
var BAR = 2.5;
var GATE_X = 0.63;
var INK = "rgba(234,228,216,";
var ACC = "rgba(255,122,69,";
var DAT = "rgba(90,209,200,";
var WRN = "rgba(245,196,81,";
var reel = [];
var seed = Math.random() * 90;
function comb(k) {
var out = [];
for (var t = 0; t < TEETH; t++) {
out.push(0.2 + Math.abs(Math.sin(k * 7.31 + t * 1.907)) * 0.8);
}
return out;
}
function spawn() {
var k = Math.random() * 90;
var honest = Math.random() > 0.27;
reel.push({
x: -0.08,
claims: comb(honest ? k : k + 13.4),
derives: comb(k),
honest: honest,
state: 0, // 0 travelling · 1 being replayed · 2 refused · 3 accepted
hold: 0,
drop: 0,
spin: (Math.random() - HALF) * 0.6,
});
}
spawn();
function size() {
var r = cv.getBoundingClientRect();
var d = Math.min(window.devicePixelRatio || 1, BAR - HALF);
W = Math.max(r.width, 60);
H = Math.max(r.height, 60);
cv.width = Math.round(W * d);
cv.height = Math.round(H * d);
g.setTransform(d, 0, 0, d, 0, 0);
}
function drawComb(cx, cy, wide, tall, teeth, alpha, colour) {
var gap = wide / TEETH;
for (var t = 0; t < TEETH; t++) {
var hgt = teeth[t] * tall;
g.fillStyle = colour + alpha + ")";
g.fillRect(cx + t * gap, cy - hgt * HALF, Math.max(gap * 0.42, 1.2), hgt);
}
}
function draw() {
g.clearRect(0, 0, W, H);
var lane = H * HALF;
var gx = W * GATE_X;
var bw = W * 0.23;
var bh = Math.min(H * 0.17, 58);
g.fillStyle = INK + "0.13)";
g.fillRect(0, lane - 1, W, 1);
g.fillStyle = ACC + "0.75)";
g.fillRect(gx, lane - H * 0.32, BAR + 1, H * 0.64);
g.fillStyle = ACC + "0.22)";
g.fillRect(gx - BAR, lane - H * 0.32, BAR, H * 0.64);
g.fillStyle = ACC + "0.16)";
for (var q = 0; q < TEETH; q++) {
var qy = lane - H * 0.28 + q * (H * 0.56 / TEETH);
g.fillRect(gx - 6, qy, 5, 1);
}
for (var i = 0; i < reel.length; i++) {
var b = reel[i];
var x = b.x * W;
var y = lane + b.drop;
var refused = b.state === 2;
var col = refused ? WRN : b.state === 3 ? DAT : ACC;
g.save();
g.translate(x, y);
if (refused) g.rotate(b.spin * Math.min(b.drop / 40, 1));
g.fillStyle = col + "0.17)";
g.fillRect(-bw * HALF, -bh * HALF, bw, bh);
g.strokeStyle = col + (refused ? "0.92)" : "0.7)");
g.lineWidth = 1;
g.strokeRect(-bw * HALF, -bh * HALF, bw, bh);
g.fillStyle = col + "0.42)";
for (var h = 0; h < 4; h++) {
var hy = -bh * HALF + bh * 0.16 + h * (bh * 0.23);
g.fillRect(-bw * HALF + 3, hy, 3, 3);
g.fillRect(bw * HALF - 6, hy, 3, 3);
}
drawComb(-bw * 0.29, 0, bw * 0.58, bh * 0.46, b.claims, refused ? "0.8" : "0.6", col);
g.restore();
if (b.state === 1 || refused) {
var lift = Math.min(b.hold / 14, 1);
drawComb(
gx + 12,
lane - H * 0.19,
bw * 0.72,
bh * 0.5 * lift,
b.derives,
refused ? "0.75" : "0.55",
refused ? WRN : DAT
);
g.fillStyle = (refused ? WRN : DAT) + (0.3 * lift) + ")";
g.fillRect(gx + 12, lane - H * 0.19 + bh * 0.34, bw * 0.72, 1);
}
}
}
function same(a, b) {
for (var t = 0; t < TEETH; t++) if (Math.abs(a[t] - b[t]) > 0.02) return false;
return true;
}
function tick() {
var gx = GATE_X;
for (var i = reel.length - 1; i >= 0; i--) {
var b = reel[i];
if (b.state === 0) {
b.x += 0.0068;
if (b.x >= gx - 0.11) {
b.state = 1;
b.hold = 0;
}
} else if (b.state === 1) {
b.hold += 1;
if (b.hold > 34) b.state = same(b.claims, b.derives) ? 3 : 2;
} else if (b.state === 3) {
b.x += 0.019;
if (b.x > 1.25) reel.splice(i, 1);
} else {
b.hold += 1;
b.drop += 2.9;
if (b.drop > H * 0.7) reel.splice(i, 1);
}
}
var travelling = 0;
for (var w = 0; w < reel.length; w++) if (reel[w].state < 2) travelling++;
var lastX = -1;
for (var v = 0; v < reel.length; v++) if (reel[v].state === 0 && reel[v].x > lastX) lastX = reel[v].x;
if (travelling < 3 && (lastX < 0 || lastX > 0.22)) spawn();
draw();
}
size();
draw();
if (STILL) return;
var timer = null;
function run() {
if (timer === null) timer = window.setInterval(tick, 1000 / FPS);
}
function halt() {
if (timer !== null) {
window.clearInterval(timer);
timer = null;
}
}
document.addEventListener("visibilitychange", function () {
if (document.hidden) halt();
else run();
});
window.addEventListener("resize", function () {
size();
draw();
});
if (!document.hidden) run();
})();
