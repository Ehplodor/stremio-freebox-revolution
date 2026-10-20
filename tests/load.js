// Charge un fichier JS de l'appli QML (".pragma library", fonctions globales) dans Node.
"use strict";
const fs = require("fs");
const path = require("path");
const vm = require("vm");

module.exports = function load(relPath) {
    const file = path.join(__dirname, "..", relPath);
    const code = fs.readFileSync(file, "utf8").replace(/^\s*\.(pragma|import)\b.*$/gm, "");
    const context = vm.createContext({ console: console });
    vm.runInContext(code, context, { filename: file });
    return context;
};

module.exports.fixture = function fixture(name) {
    return JSON.parse(fs.readFileSync(path.join(__dirname, "fixtures", name), "utf8"));
};
