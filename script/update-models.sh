#!/usr/bin/env bash
set -euo pipefail

# update-models.sh — Sync OpenCode and Pi agent configs with running llama-server endpoints
# Endpoints:
#   llama-cpp1: http://localhost:8080/v1/models (Primary / P100)
#   llama-cpp2: http://localhost:8081/v1/models (Secondary / 1060)

OPENCODE_CONFIG="${HOME}/.config/opencode/opencode.jsonc"
PI_CONFIG="${HOME}/.pi/agent/models.json"

HOST="127.0.0.1"
PORT1="8080"
PORT2="8081"
DRY_RUN=0

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Sync available models from llama-server endpoints to:
  - ${OPENCODE_CONFIG}
  - ${PI_CONFIG}

Options:
  --dry-run       Show discovered models and planned updates without modifying files
  --host <ip>     Server host (default: 127.0.0.1)
  --port1 <port>  Primary server port (default: 8080)
  --port2 <port>  Secondary server port (default: 8081)
  -h, --help      Show this help message
EOF
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        --host)
            HOST="$2"
            shift 2
            ;;
        --port1)
            PORT1="$2"
            shift 2
            ;;
        --port2)
            PORT2="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown argument: $1" >&2
            usage
            ;;
    esac
done

python3 - "$HOST" "$PORT1" "$PORT2" "$DRY_RUN" "$OPENCODE_CONFIG" "$PI_CONFIG" << 'EOF'
import sys, os, urllib.request, json, re, copy, shutil

host = sys.argv[1]
port1 = sys.argv[2]
port2 = sys.argv[3]
dry_run = sys.argv[4] == "1"
opencode_path = os.path.expanduser(sys.argv[5])
pi_path = os.path.expanduser(sys.argv[6])

url1 = f"http://{host}:{port1}/v1/models"
url2 = f"http://{host}:{port2}/v1/models"

def strip_jsonc_comments(text):
    def replacer(match):
        s = match.group(0)
        if s.startswith('/'):
            return ''
        return s
    pattern = re.compile(
        r'//.*?$|/\*.*?\*/|"(?:\\.|[^\\"])*"',
        re.DOTALL | re.MULTILINE
    )
    stripped = re.sub(pattern, replacer, text)
    stripped = re.sub(r',\s*([\]}])', r'\1', stripped)
    return stripped

def fetch_endpoint(url):
    try:
        req = urllib.request.Request(url, headers={'User-Agent': 'update-models/1.0'})
        with urllib.request.urlopen(req, timeout=5) as resp:
            data = json.load(resp)
            return data.get("data", [])
    except Exception as e:
        return None

def extract_ctx_size(m):
    args = m.get("status", {}).get("args", [])
    if "--ctx-size" in args:
        idx = args.index("--ctx-size")
        if idx + 1 < len(args):
            try:
                return int(args[idx + 1])
            except ValueError:
                pass
    if "-c" in args:
        idx = args.index("-c")
        if idx + 1 < len(args):
            try:
                return int(args[idx + 1])
            except ValueError:
                pass
    preset = m.get("status", {}).get("preset", "")
    for line in preset.splitlines():
        line = line.strip()
        if line.startswith("ctx-size =") or line.startswith("c ="):
            try:
                return int(line.split("=")[1].strip())
            except ValueError:
                pass
    return m.get("context_length", 65536)

def is_vision_model(m):
    args = m.get("status", {}).get("args", [])
    if "--mmproj" in args:
        return True
    input_mods = m.get("architecture", {}).get("input_modalities", [])
    if "image" in input_mods:
        return True
    preset = m.get("status", {}).get("preset", "")
    for line in preset.splitlines():
        line = line.strip()
        if line.startswith("mmproj ="):
            return True
    return False

def has_reasoning(m):
    args = m.get("status", {}).get("args", [])
    arg_str = " ".join(args)
    if "preserve_thinking" in arg_str or "reasoning_effort" in arg_str or "enable_thinking" in arg_str:
        return True
    preset = m.get("status", {}).get("preset", "")
    if "preserve_thinking" in preset or "reasoning_effort" in preset or "enable_thinking" in preset:
        return True
    return False

def generate_friendly_name(filename):
    KNOWN_NAMES = {
        "NVIDIA-Nemotron-Labs-3-Elastic-12B-A2B.i1-Q5_K_M.gguf": "Nemotron 3 Elastic 12B-A2B (Q5_K_M)",
        "Nemotron-3.5-Bolt-E4B-DFlash-BF16.gguf": "Nemotron 3.5 Bolt E4B DFlash (BF16)",
        "Swift-1.5-Qwen3.8-27B-GSQ-RCO-IQ3_S-mtp.gguf": "Swift 1.5 Qwen3.8 27B MTP (IQ3_S)",
        "Qwen3.8-27B-UD3.1-Q3_K_XL.gguf": "Qwen3.8 27B (UD3.1 Q3_K_XL)",
        "gemma-4-12B-it-qat-UD-Q4_K_XL.gguf": "Gemma 4 12B IT (UD Q4_K_XL)",
        "gemma-4-E4B-it-qat-UD-Q4_K_XL.gguf": "Gemma 4 E4B IT (UD Q4_K_XL)",
        "gemma-4-E4B-it-qat-UD-Q4_K_XL-mtp.gguf": "Gemma 4 E4B IT MTP (UD Q4_K_XL)",
        "gemma-4-E4B-it-dspark.gguf": "Gemma 4 E4B IT DSpark",
        "Qwen3.8-27B-DFlash2-Q4_K_M.gguf": "Qwen3.8 27B DFlash2 (Q4_K_M)",
        "Qwen3.8-27B-GSQ-RCO-IQ3_XXS-mtp.gguf": "Qwen3.8 27B GSQ-RCO MTP (IQ3_XXS)",
        "Whittle-Next-27B-A3B.Q4_K_S.gguf": "Whittle Next 27B-A3B (Q4_K_S)",
    }
    if filename in KNOWN_NAMES:
        return KNOWN_NAMES[filename]

    clean = filename
    if clean.endswith(".gguf"):
        clean = clean[:-5]
    if clean.startswith("NVIDIA-"):
        clean = clean[7:]
    
    is_mtp = False
    if clean.endswith("-mtp"):
        is_mtp = True
        clean = clean[:-4]
    
    quant_match = re.search(r'[\.\-](?:i[0-9]\-)?((?:IQ|Q)[0-9]_[A-Za-z0-9_]+|BF16|F16|F32)$', clean)
    quant = ""
    if quant_match:
        quant = quant_match.group(1)
        clean = clean[:quant_match.start()]
    
    ud_match = re.search(r'[\.\-](UD[0-9\.]*)$', clean, re.IGNORECASE)
    ud_str = ""
    if ud_match:
        ud_str = ud_match.group(1).upper()
        clean = clean[:ud_match.start()]

    clean = re.sub(r'[\.\-]qat', '', clean, flags=re.IGNORECASE)
    
    parts = clean.replace('_', ' ').replace('-', ' ').split()
    title_parts = []
    for p in parts:
        if p.lower() == 'it':
            title_parts.append('IT')
        elif p.lower().startswith('dflash'):
            title_parts.append('DFlash' + p[6:])
        elif p.lower() == 'dspark':
            title_parts.append('DSpark')
        elif p.isupper():
            title_parts.append(p)
        elif any(c.isupper() for c in p[1:]):
            title_parts.append(p)
        else:
            title_parts.append(p.capitalize())
    
    base = " ".join(title_parts)
    if is_mtp:
        base += " MTP"
    
    q_parts = []
    if ud_str:
        q_parts.append(ud_str)
    if quant:
        q_parts.append(quant)
    
    if q_parts:
        return f"{base} ({' '.join(q_parts)})"
    return base

print(f"Connecting to endpoints...")
m1 = fetch_endpoint(url1)
m2 = fetch_endpoint(url2)

if m1 is None and m2 is None:
    print(f"[ERROR] Both endpoints ({url1} and {url2}) are unreachable! Aborting.", file=sys.stderr)
    sys.exit(1)

if m1 is not None:
    print(f"[✓] Primary ({url1}): {len(m1)} models found")
    for m in m1:
        print(f"    - {m['id']} (ctx: {extract_ctx_size(m)}, tags: {m.get('tags', [])})")
else:
    print(f"[!] Primary ({url1}) unreachable, keeping existing config.")

if m2 is not None:
    print(f"[✓] Secondary ({url2}): {len(m2)} models found")
    for m in m2:
        print(f"    - {m['id']} (ctx: {extract_ctx_size(m)}, tags: {m.get('tags', [])})")
else:
    print(f"[!] Secondary ({url2}) unreachable, keeping existing config.")

# Load OpenCode config
opencode_cfg = {}
if os.path.exists(opencode_path):
    with open(opencode_path, "r", encoding="utf-8") as f:
        try:
            opencode_cfg = json.loads(strip_jsonc_comments(f.read()))
        except Exception as e:
            print(f"[ERROR] Failed to parse {opencode_path}: {e}", file=sys.stderr)
            sys.exit(1)
else:
    print(f"[WARN] OpenCode config not found at {opencode_path}, will create new.", file=sys.stderr)
    opencode_cfg = {
        "$schema": "https://opencode.ai/config.json",
        "provider": {}
    }

# Load Pi config
pi_cfg = {}
if os.path.exists(pi_path):
    with open(pi_path, "r", encoding="utf-8") as f:
        try:
            pi_cfg = json.load(f)
        except Exception as e:
            print(f"[ERROR] Failed to parse {pi_path}: {e}", file=sys.stderr)
            sys.exit(1)
else:
    print(f"[WARN] Pi config not found at {pi_path}, will create new.", file=sys.stderr)
    pi_cfg = {"providers": {}}

# Update OpenCode
def update_opencode_provider(prov_key, models_list, default_port):
    if "provider" not in opencode_cfg:
        opencode_cfg["provider"] = {}
    if prov_key not in opencode_cfg["provider"]:
        opencode_cfg["provider"][prov_key] = {
            "npm": "@ai-sdk/openai-compatible",
            "name": f"{prov_key} (:{default_port})",
            "options": {
                "baseURL": f"http://localhost:{default_port}/v1",
                "apiKey": "not-needed",
                "timeout": 600000
            },
            "models": {}
        }
    old_models = opencode_cfg["provider"][prov_key].get("models", {})
    new_models = {}
    for m in models_list:
        mid = m["id"]
        ctx = extract_ctx_size(m)
        is_vis = is_vision_model(m)
        reasoning = has_reasoning(m)
        
        entry = {}
        if mid in old_models:
            entry = copy.deepcopy(old_models[mid])
            entry.setdefault("limit", {})["context"] = ctx
            entry["limit"].setdefault("output", 8192)
        else:
            entry["name"] = generate_friendly_name(mid)
            entry["limit"] = {"context": ctx, "output": 8192}
        
        if is_vis:
            entry["modalities"] = {"input": ["text", "image"], "output": ["text"]}
        elif "modalities" in entry:
            del entry["modalities"]
            
        if reasoning and "variants" not in entry:
            entry["variants"] = {"xhigh": {"reasoningEffort": "xhigh"}}
            
        new_models[mid] = entry
    opencode_cfg["provider"][prov_key]["models"] = new_models

if m1 is not None:
    update_opencode_provider("llama-cpp1", m1, port1)
if m2 is not None:
    update_opencode_provider("llama-cpp2", m2, port2)

# Verify default model in OpenCode
curr_model = opencode_cfg.get("model", "")
valid_models = []
for pkey in ["llama-cpp1", "llama-cpp2"]:
    if pkey in opencode_cfg.get("provider", {}):
        for mid in opencode_cfg["provider"][pkey].get("models", {}):
            valid_models.append(f"{pkey}/{mid}")
if curr_model not in valid_models and valid_models:
    opencode_cfg["model"] = valid_models[0]
    print(f"[!] Default OpenCode model reset to: {opencode_cfg['model']}")

# Update Pi agent
def update_pi_provider(prov_key, models_list, default_port):
    if "providers" not in pi_cfg:
        pi_cfg["providers"] = {}
    if prov_key not in pi_cfg["providers"]:
        pi_cfg["providers"][prov_key] = {
            "baseUrl": f"http://localhost:{default_port}/v1",
            "api": "openai-completions",
            "apiKey": "not-needed",
            "models": []
        }
    old_models = {m["id"]: m for m in pi_cfg["providers"][prov_key].get("models", []) if "id" in m}
    new_list = []
    for m in models_list:
        mid = m["id"]
        ctx = extract_ctx_size(m)
        is_vis = is_vision_model(m)
        tags = m.get("tags", [])
        
        if mid in old_models:
            entry = copy.deepcopy(old_models[mid])
            entry["contextWindow"] = ctx
            entry["tags"] = tags
            entry["input"] = ["text", "image"] if is_vis else ["text"]
        else:
            entry = {
                "id": mid,
                "contextWindow": ctx,
                "input": ["text", "image"] if is_vis else ["text"],
                "tags": tags,
                "maxTokens": 8192
            }
        new_list.append(entry)
    pi_cfg["providers"][prov_key]["models"] = new_list

if m1 is not None:
    update_pi_provider("llama-cpp1", m1, port1)
if m2 is not None:
    update_pi_provider("llama-cpp2", m2, port2)

if dry_run:
    print("\n--- [DRY RUN] OpenCode config ---")
    print(json.dumps(opencode_cfg, indent=2))
    print("\n--- [DRY RUN] Pi Agent config ---")
    print(json.dumps(pi_cfg, indent=2))
    print("\nDry-run complete. No files were modified.")
    sys.exit(0)

# Write OpenCode config with backup
os.makedirs(os.path.dirname(opencode_path), exist_ok=True)
if os.path.exists(opencode_path):
    bak_path = opencode_path + ".bak"
    shutil.copy2(opencode_path, bak_path)
    print(f"[✓] Backup created: {bak_path}")

with open(opencode_path, "w", encoding="utf-8") as f:
    json.dump(opencode_cfg, f, indent=2)
    f.write("\n")
print(f"[✓] Updated {opencode_path}")

# Write Pi config with backup
os.makedirs(os.path.dirname(pi_path), exist_ok=True)
if os.path.exists(pi_path):
    bak_path = pi_path + ".bak"
    shutil.copy2(pi_path, bak_path)
    print(f"[✓] Backup created: {bak_path}")

with open(pi_path, "w", encoding="utf-8") as f:
    json.dump(pi_cfg, f, indent=2)
    f.write("\n")
print(f"[✓] Updated {pi_path}")

print("Update completed successfully.")
EOF
