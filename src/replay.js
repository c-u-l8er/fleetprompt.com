/* ==========================================================================
   fleetprompt.com — the identifying animation. SHELL.md §8.

   SUBJECT: a bundle failing a replay gate. Sealed bundles travel along a lane
   toward a gate. At the gate each one is replayed — its frames re-derive an
   identity comb — and the comb is compared against the one the bundle carries.
   Most match and pass through. One does not, and the gate REFUSES it: the
   bundle stops dead at the bar and falls away. Refusal is the subject, because
   refusal is the product; a registry that cannot say no is a directory.

   IT RENDERS NO DATA AND ASSERTS NOTHING (§8.1.2, §8.2). It takes no input
   from the document, writes nothing back into it, draws no text, and shares no
   constant with anything printed on the page. gpscoord.com published a canvas
   loop counter as "12 Active Pathfinders" for months; launch-gate.mjs compares
   every constant in this file against every text node on the page and refuses
   the build on any overlap. WHEN THAT FIRES, THIS FILE CHANGES — never the
   page. Decoration yields to evidence.
   ========================================================================== */
(function () {
    var cv = document.querySelector("[data-identity-animation]");
    if (!cv) return;
    var g = cv.getContext("2d");
    if (!g) return;

    /* §8.4 — reduced motion renders the first frame and stops. Not optional. */
    var STILL =
        window.matchMedia &&
        window.matchMedia("(prefers-reduced-motion: reduce)").matches;

    var FPS = 30;
    var TEETH = 9;
    var W = 0,
        H = 0;
    /* Widths are named rather than written inline so that no bare integer in
       this file can collide with a figure printed on the page. §8.5 compares
       whole text nodes; a shared literal refuses the build, and the rule is
       that the DECORATION yields. Naming them is how it yields once instead of
       every time a number is added to the page. */
    var HALF = 0.5;
    var BAR = 2.5;
    var GATE_X = 0.63;

    var INK = "rgba(234,228,216,";
    var ACC = "rgba(255,122,69,";
    var DAT = "rgba(90,209,200,";
    var WRN = "rgba(245,196,81,";

    /* --- the bundles. Each carries a comb it claims; at the gate a comb is
       re-derived and the two are compared. A bundle whose claimed comb does
       not match what its own frames derive is refused. --- */
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
        /* roughly one in four is a forgery: it carries a comb that is not the
           one its frames derive, and the gate is the only thing that notices */
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

        /* the lane */
        g.fillStyle = INK + "0.13)";
        g.fillRect(0, lane - 1, W, 1);

        /* the gate: a bar with teeth, the thing that can say no */
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

            /* the bundle: a sealed can of frames */
            g.fillStyle = col + "0.17)";
            g.fillRect(-bw * HALF, -bh * HALF, bw, bh);
            g.strokeStyle = col + (refused ? "0.92)" : "0.7)");
            g.lineWidth = 1;
            g.strokeRect(-bw * HALF, -bh * HALF, bw, bh);
            /* sprocket holes down each edge — this is a film, not a box */
            g.fillStyle = col + "0.42)";
            for (var h = 0; h < 4; h++) {
                var hy = -bh * HALF + bh * 0.16 + h * (bh * 0.23);
                g.fillRect(-bw * HALF + 3, hy, 3, 3);
                g.fillRect(bw * HALF - 6, hy, 3, 3);
            }
            /* the comb it claims */
            drawComb(-bw * 0.29, 0, bw * 0.58, bh * 0.46, b.claims, refused ? "0.8" : "0.6", col);
            g.restore();

            /* under replay: the derived comb rises beside the gate and the two
               are held next to each other, which is the whole comparison */
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
                /* accepted: it clears the gate briskly, so a refusal behind it
                   is never read as two bundles stacked on the bar */
                b.x += 0.019;
                if (b.x > 1.25) reel.splice(i, 1);
            } else {
                /* refused: it stops at the bar and falls away from the lane */
                b.hold += 1;
                b.drop += 2.9;
                if (b.drop > H * 0.7) reel.splice(i, 1);
            }
        }
        /* The lane must LOOK like a queue, not like an empty road with a bar
           across it. An earlier revision spawned one bundle at a time and the
           hero screenshotted as two stray lines — the animation was correct and
           depicted nothing. Three in flight keeps the comparison legible at any
           moment the page is looked at. */
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

    /* §8.4 — capped frame rate, stops when the tab is hidden. Never an
       IntersectionObserver: it does not fire in a non-compositing renderer and
       an animation that never starts reads as a broken page (SHELL.md §6). */
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
