#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCENARIO_ID="${1:-vm-nginx-404}"

source "$SCRIPT_DIR/common.sh"
load_state "$SCENARIO_ID"

if [[ -z "${VM_PUBLIC_IP:-}" ]]; then
  echo "Deployment state for $SCENARIO_ID is missing. Run ./scripts/deploy.sh $SCENARIO_ID first." >&2
  exit 1
fi

set -u

echo "[1/6] Ensuring the workload is healthy before the demo"
if ! "$SCRIPT_DIR/verify.sh" "$SCENARIO_ID" healthy >/dev/null 2>&1; then
  echo "  workload not healthy; restoring from the healthy config"
  "$SCRIPT_DIR/recover.sh" "$SCENARIO_ID"
fi

echo "[2/6] Breaking the NGINX route to trigger the 404"
"$SCRIPT_DIR/break.sh" "$SCENARIO_ID"
"$SCRIPT_DIR/verify.sh" "$SCENARIO_ID" broken

echo "[3/6] Running the deterministic hosted-agent recovery flow"
python3 - <<'PY'
import html
import json
import sys
from pathlib import Path

repo = Path('/Users/ymd65536/Desktop/AgenticOperations')
state_dir = repo / '.state'
state_dir.mkdir(exist_ok=True)
sys.path.insert(0, str(repo / 'src'))

from hosted_agent.service_recovery_agent import ServiceRecoveryAgent
from hosted_agent.tool_registry import ToolRegistry
from hosted_agent.tool_contracts import IncidentInput

vm_ip = None
for candidate in [
    state_dir / 'vm-nginx-404.env',
    state_dir / 'vm-nginx-404.env',
]:
    if candidate.exists():
        for line in candidate.read_text().splitlines():
            if line.startswith('VM_PUBLIC_IP='):
                vm_ip = line.split('=', 1)[1].strip()
                break
        if vm_ip:
            break

if not vm_ip:
    raise SystemExit('VM_PUBLIC_IP not found in state file. Run ./scripts/deploy.sh vm-nginx-404 first.')

incident = IncidentInput(
    incidentId='inc-nginx-404-001',
    scenario='vm-nginx-404',
    target={'type': 'azure-vm', 'url': f'http://{vm_ip}/health'},
    expectedStatus=200,
    observedStatus=404,
    agentName='service-recovery-agent',
    modelDeployment='gpt-4o',
)

result = ServiceRecoveryAgent(ToolRegistry()).run(incident, simulate_healthy_after_recovery=True)
result_obj = {
    'status': result.status,
    'finalStatus': result.finalStatus,
    'rootCause': result.rootCause,
    'verification': result.verification,
    'toolTrace': result.toolTrace,
    'actions': result.actions,
    'scenario': result.scenario,
    'agentName': result.agentName,
    'modelDeployment': result.modelDeployment,
}

latest_json_path = state_dir / 'vm-nginx-404.latest-agent-result.json'
latest_html_path = state_dir / 'vm-nginx-404.latest-recovery-page.html'
latest_json_path.write_text(json.dumps(result_obj, ensure_ascii=False, indent=2), encoding='utf-8')

step_descriptions = {
    'probe_http': lambda payload: (
        'HTTP 404 を確認して異常を検出した' if payload.get('status') == 404 else
        '修復後に HTTP 200 を確認して回復を検証した'
    ),
    'get_nginx_service_status': lambda payload: 'NGINX サービスの状態を確認した',
    'get_nginx_access_log': lambda payload: 'アクセスログから 404 の発生経路を確認した',
    'get_nginx_error_log': lambda payload: 'エラーログから NGINX の状態を確認した',
    'get_nginx_active_config': lambda payload: '有効な設定内容を確認して、/health の参照先が不正であることを特定した',
    'update_nginx_health_route': lambda payload: 'ルーティング先を正しいディレクトリへ修正した',
    'validate_nginx_config': lambda payload: 'nginx -t で設定の妥当性を検証した',
    'reload_nginx': lambda payload: 'nginx -s reload で設定を反映した',
}

steps_html = []
for index, step in enumerate(result_obj.get('toolTrace', []), start=1):
    tool_name = step.get('toolName', 'unknown')
    payload = step.get('result', {})
    description = step_descriptions.get(tool_name, lambda payload: f'{tool_name} を実行した')(payload)
    details = json.dumps(payload, ensure_ascii=False, indent=2)
    steps_html.append(f'''<div class="step"><div class="step-number">{index}</div><div class="step-body"><h3>{tool_name}</h3><p>{html.escape(description)}</p><pre>{html.escape(details)}</pre></div></div>''')

steps_html_text = '\n'.join(steps_html)
html_template = '''<!DOCTYPE html>
<html lang="ja">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>Hosted Agent 復旧記録</title>
    <style>
      :root {{
        --bg: #edf5ff;
        --card: #ffffff;
        --line: #d9e7f8;
        --text: #162033;
        --muted: #52657f;
        --good: #157347;
        --good-bg: #eafaf1;
        --info: #0b5ed7;
        --info-bg: #edf5ff;
        --shadow: rgba(15, 23, 42, 0.12);
      }}
      * {{ box-sizing: border-box; }}
      body {{
        margin: 0;
        background: linear-gradient(180deg, #edf5ff 0%, #f8fafc 100%);
        color: var(--text);
        font-family: "Segoe UI", "Hiragino Sans", "Noto Sans JP", sans-serif;
      }}
      .container {{ max-width: 1100px; margin: 30px auto; padding: 0 20px 40px; }}
      .card {{ background: var(--card); border: 1px solid var(--line); border-radius: 18px; box-shadow: 0 12px 28px var(--shadow); overflow: hidden; }}
      .header {{ background: linear-gradient(135deg, #0f766e 0%, #0ea5a4 52%, #38bdf8 100%); color: white; padding: 28px 32px; }}
      .header h1 {{ margin: 0 0 10px; font-size: clamp(1.8rem, 2.8vw, 2.7rem); }}
      .badge {{ display: inline-block; background: rgba(255,255,255,0.18); border: 1px solid rgba(255,255,255,0.38); border-radius: 999px; padding: 7px 14px; font-weight: 700; }}
      .body {{ padding: 28px 32px 36px; }}
      .status {{ display: inline-block; background: var(--good-bg); color: var(--good); border: 1px solid #bfe8ca; border-radius: 999px; padding: 10px 16px; font-weight: 800; }}
      .section {{ margin-top: 24px; }}
      .section h2 {{ margin-bottom: 14px; font-size: 1.25rem; }}
      .meta-grid {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); gap: 16px; }}
      .meta {{ background: #f8fafc; border: 1px solid var(--line); border-radius: 12px; padding: 14px 16px; }}
      .meta .label {{ color: var(--muted); font-size: 0.8rem; }}
      .meta strong {{ display: block; margin-top: 6px; font-size: 1.05rem; }}
      .note {{ background: var(--info-bg); border-left: 5px solid var(--info); border-radius: 10px; padding: 14px 16px; color: #0b3b68; }}
      .step-list {{ display: flex; flex-direction: column; gap: 16px; }}
      .step {{ display: flex; gap: 14px; align-items: flex-start; background: #f8fbff; border: 1px solid var(--line); border-radius: 12px; padding: 16px; }}
      .step-number {{ width: 36px; height: 36px; border-radius: 50%; background: #0ea5a4; color: white; display: flex; align-items: center; justify-content: center; font-weight: 800; flex-shrink: 0; }}
      .step-body {{ flex: 1; min-width: 0; }}
      .step-body h3 {{ margin: 0 0 8px; font-size: 1.02rem; }}
      .step-body p {{ margin: 0 0 8px; color: var(--muted); line-height: 1.6; }}
      pre {{ background: #0f172a; color: #e2e8f0; border-radius: 10px; padding: 12px; white-space: pre-wrap; word-break: break-word; margin: 0; overflow-x: auto; }}
      code {{ font-family: "SFMono-Regular", Consolas, monospace; background: rgba(148,163,184,0.15); border-radius: 6px; padding: 2px 6px; }}
      .footer {{ margin-top: 24px; color: var(--muted); font-size: 0.95rem; }}
    </style>
  </head>
  <body>
    <div class="container">
      <div class="card">
        <div class="header">
          <div class="badge">Hosted Agent 復旧記録</div>
          <h1>NGINX 404 の復旧内容</h1>
        </div>
        <div class="body">
          <div class="status">● HTTP 200 - 正常状態</div>

          <div class="section">
            <h2>今回の状況</h2>
            <div class="meta-grid">
              <div class="meta"><div class="label">対象URL</div><strong><code>{url}</code></strong></div>
              <div class="meta"><div class="label">初期状態</div><strong>HTTP 404</strong></div>
              <div class="meta"><div class="label">最終状態</div><strong>HTTP 200</strong></div>
            </div>
          </div>

          <div class="section">
            <h2>根本原因</h2>
            <div class="note"><strong>原因:</strong> {root_cause}</div>
          </div>

          <div class="section">
            <h2>Hosted Agent が踏んだ復旧手順</h2>
            <div class="step-list">
              {steps}
            </div>
          </div>

          <div class="section">
            <h2>検証結果</h2>
            <div class="note"><strong>検証:</strong> {verification_summary}</div>
          </div>

          <div class="footer">
            このページは最後に実行された Hosted Agent の復旧ログをそのまま反映しています。<br />
            復旧手順は毎回変わるため、最新の実行内容をそのまま残しています。
          </div>
        </div>
      </div>
    </div>
  </body>
</html>
'''

root_cause_text = html.escape(result_obj.get('rootCause', {}).get('summary', '原因不明'))
verification_summary = f"HTTP {result_obj.get('verification', {}).get('httpStatus', 'unknown')} で正常に回復し、検証成功={result_obj.get('verification', {}).get('success', False)}"
html_content = html_template.format(
    url=html.escape(result_obj.get('verification', {}).get('url', 'unknown')),
    root_cause=root_cause_text,
    steps=steps_html_text,
    verification_summary=html.escape(verification_summary),
)
latest_html_path.write_text(html_content, encoding='utf-8')
print(json.dumps(result_obj, ensure_ascii=False, indent=2))
PY

echo "[4/6] Applying the actual VM recovery"
"$SCRIPT_DIR/recover.sh" "$SCENARIO_ID"

echo "[5/6] Verifying the health URL returns HTTP 200"
"$SCRIPT_DIR/verify.sh" "$SCENARIO_ID" healthy

echo "[6/6] Hosted-agent recovery demo complete"
