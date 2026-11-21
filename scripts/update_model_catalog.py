#!/usr/bin/env python3
"""Build the passive model lookup tables from the checkouts in Catalog-Sources.txt."""

import argparse
import ast
import json
from pathlib import Path
import re

BRAND_CODES = {
    r"SM-[A-Z]\d{3,4}[A-Z0-9/]*|GT-[A-Z]\d{4}[A-Z0-9]*|SCH-[A-Z]\d{3,4}[A-Z0-9]*|SHV-[A-Z]\d{3,4}[A-Z0-9]*": {"samsung"},
    r"(?:MI|M)\d{4}[A-Z0-9]{3,9}|\d{5}[A-Z0-9]{4,10}|(?:POCO )?F\d{1,2}[A-Z0-9]{4,10}": {"xiaomi", "redmi", "poco"},
    r"(?:HUAWEI )?[A-Z0-9]{3,5}-(?:AL|AN|TL|TN|LX|L|W|N|C|X)\d{1,3}[A-Z0-9]*": {"huawei", "honor"},
    r"CPH\d{4}|P[A-Z]{2}\d{3}|OPD\d{4}": {"oppo", "oneplus"},
    r"RMX\d{4}": {"realme", "oppo"},
    r"V\d{4}[A-Z]{0,3}|I\d{4}[A-Z]{0,3}": {"vivo", "iqoo"},
    r"XT\d{4}(?:-\d{1,2})?|LM-[A-Z]\d{3,4}[A-Z0-9]*|XQ-[A-Z]{2}\d{2}": {"motorola", "lge", "sony"},
    r"ASUS_[A-Z0-9]{4,14}|ZS\d{3}[A-Z]{1,3}": {"asus"},
    r"A\d{3}[A-Z]?": {"nothing", "cmf by nothing"},
    r"A\d{4}[A-Z]?|LENOVO (?:TB|YT|YB)-[A-Z0-9]{4,14}|(?:TB|YT|YB)-[A-Z0-9]{4,14}": {"lenovo"},
}

def android_models(path):
    models = {}
    ambiguous = set()
    patterns = [(re.compile(pattern), brands) for pattern, brands in BRAND_CODES.items()]
    for raw, details in json.loads(path.read_text()).items():
        code = raw.strip().upper()
        brand = details["brand"].strip().lower()
        name = details["name"].strip()
        if not name or any(ord(char) < 32 for char in name) or len(name) > 80:
            continue
        if not any(brand in brands and regex.fullmatch(code) for regex, brands in patterns):
            continue
        if name.upper() == code:
            continue
        if code in models and models[code] != name:
            ambiguous.add(code)
        models[code] = name
    return {code: name for code, name in models.items() if code not in ambiguous}

def apple_models(path):
    text = path.read_text()
    device_map = text.split("func mapToDevice(identifier:", 1)[1].split("public var", 1)[0]
    names = dict(re.findall(r'case \.(\w+): return "([^"\\]+)"', text))
    result = {}
    for line, symbol in re.findall(r'^\s*case (".+"): return (\w+)\s*$', device_map, re.MULTILINE):
        for code in re.findall(r'"((?:iPhone|iPod|iPad|Watch|AppleTV|RealityDevice)\d+,\d+)"', line):
            if symbol in names:
                result[code.upper()] = names[symbol]
    return result

def switchbot_models(path):
    tree = ast.parse(path.read_text())
    table = next(node.value for node in tree.body if isinstance(node, ast.AnnAssign)
                 and getattr(node.target, "id", None) == "SUPPORTED_TYPES")
    result = {}
    for raw, values in zip(table.keys, table.values, strict=True):
        code = ast.literal_eval(raw)
        if isinstance(code, str):
            code = code.encode("ascii")
        if len(code) not in (1, 4):
            continue
        fields = {ast.literal_eval(key): value for key, value in zip(values.keys, values.values, strict=True)}
        name = ast.literal_eval(fields["modelFriendlyName"])
        result[code.hex()] = name if name.lower().startswith("switchbot ") else "SwitchBot " + name
    return result

def shelly_models(path):
    return dict(re.findall(r'name == "(SB[A-Z0-9-]+)":\s+manufacturer = "Shelly"\s+name = "([^"]+)"',
                           path.read_text()))

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("android_snapshot", type=Path)
    parser.add_argument("devicekit_checkout", type=Path)
    parser.add_argument("switchbot_checkout", type=Path)
    parser.add_argument("bthome_checkout", type=Path)
    args = parser.parse_args()
    tables = {
        "android": android_models(args.android_snapshot),
        "apple": apple_models(args.devicekit_checkout / "Source/Device.generated.swift"),
        "switchbot": switchbot_models(args.switchbot_checkout / "switchbot/adv_parser.py"),
        "shelly": shelly_models(args.bthome_checkout / "src/bthome_ble/parser.py"),
    }
    if not all(tables.values()):
        parser.error("Every upstream must contribute at least one valid model")
    out = Path(__file__).resolve().parents[1] / "DormRadar/Catalog/AdditionalModelCodes.json"
    out.write_text(json.dumps(tables, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n")
    for label, entries in tables.items():
        print(label, len(entries), "codes,", len(set(entries.values())), "distinct display names")

if __name__ == "__main__":
    main()
