# Agentic Operations

このリポジトリは、Azure 上で再現可能な 404 の障害シナリオを作成し、正常状態と障害状態の切り替え、復旧、検証を自動化するための実験用ワークロードです。

## 目的

Milestone 1 では、Azure VM 上で NGINX を動かし、以下のライフサイクルを再現します。

```text
Deploy
→ HTTP 200
→ Inject routing failure
→ HTTP 404
→ Recover
→ HTTP 200
```

このリポジトリでは、AI による修復や Azure Monitor を有効化する前段として、障害が意図的に注入され、再現性と回復可能性を確認できる単一障害シナリオを作成します。

## 構成

- infra/: Bicep で定義する Azure インフラ
- src/nginx/: healthy.conf と broken.conf を含む NGINX 設定
- scenarios/vm-nginx-404/: VM + NGINX シナリオの詳細と証跡情報
- scripts/: deploy, break, recover, verify, destroy
- tests/smoke/: 実行可能な smoke test

## 主要シナリオ

- vm-nginx-404: Azure Ubuntu VM 上の NGINX に対し、設定の誤りで /health が 404 になる仕組みを再現

## 前提条件

- Azure CLI がインストール済み
- Azure サブスクリプションへログイン済み
- SSH 公開鍵がローカル環境に存在する
- 実行前に AZURE_RESOURCE_GROUP、AZURE_LOCATION、AZURE_VM_SSH_PUBLIC_KEY_PATH を必要に応じて設定

```bash
az login
export AZURE_RESOURCE_GROUP=rg-agentic-ops-dev
export AZURE_LOCATION=eastus
export AZURE_VM_SSH_PUBLIC_KEY_PATH="$HOME/.ssh/id_rsa.pub"
```

## デプロイ

```bash
./scripts/deploy.sh vm-nginx-404
```

デプロイ時に Azure VM とネットワークを作成し、NGINX をインストールして正常な構成へ設定します。

## 障害注入

```bash
./scripts/break.sh vm-nginx-404
```

本シナリオでは、NGINX サービス自体や VM 自体を止めず、Nginx の `location` 解決に失敗するような設定を置き換えることで 404 を再現します。

## 復旧

```bash
./scripts/recover.sh vm-nginx-404
```

正常な設定を再配置し、`nginx -t` と `nginx -s reload` を実行して監視対象 URL を HTTP 200 に戻します。

## 検証

### 基本シナリオの検証

```bash
./scripts/deploy.sh vm-nginx-404
./scripts/verify.sh vm-nginx-404 healthy
./scripts/break.sh vm-nginx-404
./scripts/verify.sh vm-nginx-404 broken
./scripts/recover.sh vm-nginx-404
./scripts/verify.sh vm-nginx-404 healthy
```

- healthy: 期待値 200
- broken: 期待値 404

検証スクリプトは URL、期待ステータス、実際のステータス、PASS/FAIL を標準出力へ表示し、ズレがあれば非 0 で終了します。

### Logic App 経由の検証

```bash
./scripts/deploy-alert-recovery.sh vm-nginx-404
./scripts/break.sh vm-nginx-404
./scripts/verify.sh vm-nginx-404 broken

LOGIC_APP_NAME='logic-vm-nginx-recover-1786875930'
CALLBACK_URL=$(az rest \
  --method post \
  --uri "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/rg-agentic-ops-dev/providers/Microsoft.Logic/workflows/${LOGIC_APP_NAME}/triggers/When_a_HTTP_request_is_received/listCallbackUrl?api-version=2019-05-01" \
  --query value -o tsv)

curl -sS -D - -X POST "$CALLBACK_URL" \
  -H 'Content-Type: application/json' \
  -d '{"data":{"alertContext":{"properties":{"monitoringService":"cron-health-check","statusCode":404,"url":"http://20.120.113.228/health"}}}}'
```

このテストでは、VM 側で 404 を検知した後に Logic App の callback URL を呼ぶと、回復フローが実行され、応答として以下を返します。

```json
{"status":"recovered","url":"http://20.120.113.228/health","message":"Recovered the VM NGINX configuration and validated HTTP 200."}
```

この実行後、回復状態を確認するには:

```bash
bash scripts/recover-vm-alert.sh vm-nginx-404
./scripts/verify.sh vm-nginx-404 healthy
```

## 破棄

```bash
./scripts/destroy.sh vm-nginx-404
```

## 参考コスト情報

Milestone 1 は Linux VM 1 台とネットワーク資源を利用します。開発用の最小 VM サイズと NSG を使うため、通常の開発環境のコストよりは低いですが、VM は停止していても Azure 料金が発生し得ます。リソースの削除は `destroy.sh` で実行してください。

## Hosted Agent の追加実装

このリポジトリは、既存のルールベース復旧の比較対象として、Microsoft Foundry Hosted Agent 用の安全なデモを追加します。

- 目的: HTTP 404 の事実だけを受け取り、状況確認・証拠収集・原因推定・許可された設定変更・検証まで自律的に進める
- Agent 名: service-recovery-agent
- 方式: Hosted Agent / Tool Registry / allow-list による制御
- 実装場所: src/hosted_agent, prompts/service-recovery-agent.system.md, scripts/run-agent-demo.sh
- 既存の break.sh / recover.sh / verify.sh / Logic App recovery は維持して比較可能な状態にする

## 今回実装しない対象

- Azure Functions
- Azure Static Web Apps
- Azure Monitor Alerts
- AI による AGENTS.md 変更
- 任意Shell実行
- 本番環境対応
- 人間承認UI

## 監視対象URL

監視対象は `http://<VM_PUBLIC_IP>/health` です。正常状態では `azure-agentic-ops nginx healthy` が本文に含まれます。
