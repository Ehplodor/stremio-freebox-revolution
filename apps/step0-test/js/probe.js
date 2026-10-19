// Detection du runtime QML/JavaScript de la box. ES5 uniquement :
// ce fichier doit se charger meme sur un vieux moteur V4.

// Renvoie true si le bloc d'imports QML se charge.
function canImport(parent, imports) {
    try {
        var o = Qt.createQmlObject(imports + "\nItem {}", parent, "probe");
        o.destroy();
        return true;
    } catch (e) {
        return false;
    }
}

// Plus haute version mineure importable d'un module (ex. QtQuick 2.N), -1 si aucune.
function highestMinor(parent, module, major, maxMinor, prefix) {
    var best = -1;
    for (var i = 0; i <= maxMinor; i++) {
        if (canImport(parent, prefix + "import " + module + " " + major + "." + i))
            best = i;
    }
    return best;
}

// Teste une syntaxe JS sans faire planter le fichier si le moteur ne la connait pas.
function supportsSyntax(src) {
    try {
        var f = new Function(src);
        f();
        return true;
    } catch (e) {
        return false;
    }
}

function run(parent) {
    var lines = [];
    var quick = highestMinor(parent, "QtQuick", 2, 15, "");
    // QtQuick 2.N est livre avec Qt 5.N a partir de Qt 5.2.
    lines.push("QtQuick 2." + quick + " => Qt " + (quick >= 2 ? "5." + quick + ".x environ" : "< 5.2"));

    var mm = highestMinor(parent, "QtMultimedia", 5, 15, "import QtQuick 2.0\n");
    lines.push("QtMultimedia : " + (mm >= 0 ? "5." + mm : "absent"));

    var modules = ["fbx.application 1.0", "fbx.media 1.0", "fbx.ui.control 1.0",
                   "fbx.ui.menu 1.0", "fbx.web 1.0", "fbx.async 1.0", "fbx.data 1.0",
                   "QtQuick.Controls 1.0", "QtQuick.Controls 2.0", "QtQuick.XmlListModel 2.0"];
    var ok = [], ko = [];
    for (var i = 0; i < modules.length; i++) {
        if (canImport(parent, "import QtQuick 2.0\nimport " + modules[i]))
            ok.push(modules[i]);
        else
            ko.push(modules[i]);
    }
    lines.push("Modules presents : " + ok.join(", "));
    lines.push("Modules absents : " + (ko.length ? ko.join(", ") : "aucun"));

    var js = [
        ["let/const", "let a = 1; const b = 2;"],
        ["fonctions flechees", "var f = (x) => x; f(1);"],
        ["template strings", "var s = `a${1}`;"],
        ["classes", "class A {}"],
        ["Promise", "if (typeof Promise !== 'function') throw 0;"],
        ["Object.assign", "if (typeof Object.assign !== 'function') throw 0;"],
        ["Array.prototype.find", "if (typeof [].find !== 'function') throw 0;"],
        ["JSON", "JSON.parse('{\"a\":1}');"]
    ];
    var yes = [], no = [];
    for (var j = 0; j < js.length; j++) {
        if (supportsSyntax(js[j][1]))
            yes.push(js[j][0]);
        else
            no.push(js[j][0]);
    }
    lines.push("JS OK : " + yes.join(", "));
    lines.push("JS non supporte : " + (no.length ? no.join(", ") : "rien"));

    lines.push("Qt.platform.os : " + Qt.platform.os);
    lines.push("Ecran : " + parent.width + "x" + parent.height);
    return lines;
}
