.pragma library

var LEAGUE_THEMES = {
    "FIFA.WORLD": {
        primary: "#ffd700",
        secondary: "#1a237e",
        accent: "#00bfa5",
        gradient: ["#1a237e", "#0d47a1", "#01579b"],
        text: "#ffffff",
        headerText: "#ffd700",
        special: true,
    },
    "uefa.champions": {
        primary: "#00aaff",
        secondary: "#0b1f3a",
        accent: "#ffffff",
        gradient: ["#0b1f3a", "#1a3b6d", "#0b1f3a"],
        text: "#ffffff",
        headerText: "#00aaff",
        special: true,
    },
    "uefa.euro": {
        primary: "#ffcc00",
        secondary: "#003399",
        accent: "#ff6600",
        gradient: ["#003399", "#0047b3", "#003399"],
        text: "#ffffff",
        headerText: "#ffcc00",
        special: true,
    },
    "nor.1": {
        primary: "#e30613",
        secondary: "#001f4e",
        accent: "#ffffff",
        gradient: ["#001f4e", "#00337a", "#001f4e"],
        text: "#ffffff",
        headerText: "#ffffff",
        special: false,
    },
    "ENG.1": {
        primary: "#00ff85",
        secondary: "#38003c",
        accent: "#ffffff",
        gradient: ["#38003c", "#5a005f", "#38003c"],
        text: "#ffffff",
        headerText: "#00ff85",
        special: false,
    },
    "GER.1": {
        primary: "#d3010c",
        secondary: "#1a1a1a",
        accent: "#ffffff",
        gradient: ["#1a1a1a", "#333333", "#1a1a1a"],
        text: "#ffffff",
        headerText: "#ffffff",
        special: false,
    },
    "ESP.1": {
        primary: "#ff4b00",
        secondary: "#001b35",
        accent: "#ffffff",
        gradient: ["#001b35", "#003366", "#001b35"],
        text: "#ffffff",
        headerText: "#ff4b00",
        special: false,
    },
    "ITA.1": {
        primary: "#008fd5",
        secondary: "#001b6c",
        accent: "#ffffff",
        gradient: ["#001b6c", "#003399", "#001b6c"],
        text: "#ffffff",
        headerText: "#ffffff",
        special: false,
    },
    "FRA.1": {
        primary: "#d9d9d9",
        secondary: "#12233f",
        accent: "#ffffff",
        gradient: ["#12233f", "#1f3a66", "#12233f"],
        text: "#ffffff",
        headerText: "#d9d9d9",
        special: false,
    },
    "default": {
        primary: "#4CAF50",
        secondary: "#2196F3",
        accent: "#ffffff",
        gradient: null,
        text: null,
        headerText: null,
        special: false,
    }
};

function themeFor(leagueId) {
    return LEAGUE_THEMES[leagueId] || LEAGUE_THEMES["default"];
}

function primaryColor(leagueId) {
    return themeFor(leagueId).primary;
}

function secondaryColor(leagueId) {
    return themeFor(leagueId).secondary;
}

function accentColor(leagueId) {
    return themeFor(leagueId).accent;
}

// ── Dark-mode helpers ─────────────────────────────────────────────────────
// Saturated per-league colours "vibrate" on a dark surface and cause fatigue
// (Material dark-theme guidance: use the 200-50 tones, not the 500s). These
// helpers pull a hex toward its own luma so accents stay recognisable but calm.

function _clamp(v) { return v < 0 ? 0 : (v > 255 ? 255 : Math.round(v)); }

function _parse(hex) {
    var h = (hex || "#888888").replace("#", "");
    if (h.length === 3) h = h[0]+h[0]+h[1]+h[1]+h[2]+h[2];
    return {
        r: parseInt(h.substr(0, 2), 16),
        g: parseInt(h.substr(2, 2), 16),
        b: parseInt(h.substr(4, 2), 16)
    };
}

function _hex(r, g, b) {
    function p(v) { var s = _clamp(v).toString(16); return s.length === 1 ? "0"+s : s; }
    return "#" + p(r) + p(g) + p(b);
}

// factor 0 = unchanged, 1 = fully grey. Optionally lift toward `lift` (0-255)
// so very dark primaries don't disappear on a near-black ground.
function desaturate(hex, factor, lift) {
    var c = _parse(hex);
    var luma = 0.299 * c.r + 0.587 * c.g + 0.114 * c.b;
    var f = factor === undefined ? 0.45 : factor;
    var r = c.r + (luma - c.r) * f;
    var g = c.g + (luma - c.g) * f;
    var b = c.b + (luma - c.b) * f;
    if (lift) {
        var cur = 0.299 * r + 0.587 * g + 0.114 * b;
        if (cur < lift) { var d = lift - cur; r += d; g += d; b += d; }
    }
    return _hex(r, g, b);
}

// Calm accent for a league: desaturated + lifted so it reads on dark surfaces.
function softAccent(leagueId) {
    return desaturate(themeFor(leagueId).primary, 0.4, 150);
}
