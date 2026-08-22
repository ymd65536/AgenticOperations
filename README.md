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
- scripts/: deploy, break, recover, verify, destroy, hosted-agent-guidance-flow, remote-action-channel
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
export AZURE_RESOURCE_GROUP=rg-agenticops-demo
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

## Microsoft Foundry の Hosted Agents

このリポジトリでは、既存のルールベース復旧と比較するために、Microsoft Foundry の Hosted Agent を安全な形で導入しています。

- 目的: HTTP 404 の事実を受け取り、状況確認・証跡収集・原因候補の整理・承認済み修復方針の選定・検証までを行う
- Agent 名: `service-recovery-agent`
- 実行形態: Hosted Agent / allow-list / 安全な運用境界
- 実装の位置: `src/hosted_agent`, `scripts/hosted-agent-guidance-flow.sh`, `scripts/remote-action-channel.sh`

### 安全な remote-action channel

Hosted Agent は Azure VM に対して直接 SSH で自由にログインしません。これは、任意のシェル実行や権限の乱用を防ぐためです。代わりに、許可された操作だけを実行できる安全な channel を用意しています。

```bash
./scripts/remote-action-channel.sh inspect vm-nginx-404
./scripts/remote-action-channel.sh repair vm-nginx-404
./scripts/remote-action-channel.sh verify vm-nginx-404
```

この channel で許可されている操作は次のとおりです。

- `nginx -t` による設定検証
- `nginx -s reload` による再読み込み
- 承認済み healthy config の配置
- `curl` または `verify.sh` による確認

### 一括フロー

```bash
./scripts/hosted-agent-guidance-flow.sh vm-nginx-404
```

このスクリプトは次の順で動作します。

1. 正常状態へ戻す
2. VM を壊して 404 を発生させる
3. Hosted Agent に一次調査を依頼する
4. 安全な remote-action channel で修復する
5. HTTP 200 を確認する

### Azure Foundry のセットアップと再デプロイ手順

Hosted Agent を Azure Foundry に再デプロイするには、まず対象の Azure AI / Foundry 環境に合わせて `azd` の設定を行います。実際の値は各環境で異なるため、ここでは固定名を使わずに環境変数で切り替える運用にします。

```bash
# 1) Azure にログイン
az login

# 2) エージェント定義があるディレクトリへ移動
cd foundry-agent-demo

# 3) 既存の Foundry project / model に合わせて環境変数を設定
azd env set AZURE_LOCATION "<your-region>"
azd env set AZURE_RESOURCE_GROUP "<your-resource-group>"
azd env set AZURE_AI_PROJECT_ENDPOINT "<your-project-endpoint>"
azd env set AZURE_AI_MODEL_DEPLOYMENT_NAME "<your-model-name>"
azd env set USE_EXISTING_AI_PROJECT "true"

# 4) デプロイの更新を反映
azd up --no-prompt

# 5) Hosted Agent の状態確認
azd ai agent show
```

この流れで、`service-recovery-agent` は最新の定義を Azure Foundry に反映できます。ソースコードを更新したあとも、同じ `azd up --no-prompt` を実行すれば、Hosted Agent の定義を再デプロイできます。

> 実際の Azure AI resource、Foundry project、モデル名は環境ごとに異なるため、ここでは値をそのまま埋め込まず、`azd env set` で必要な値だけを設定する運用を想定しています。
> `azure.yaml` 側では、`endpoint` やデプロイメント名をハードコードせず、`${AZURE_AI_PROJECT_ENDPOINT}` と `${AZURE_AI_MODEL_DEPLOYMENT_NAME}` のような環境変数参照にしておくと移植しやすくなります。
> `azd ai agent redeploy` が使えない場合も、`azd up --no-prompt` を使って再デプロイするのが安全で簡単です。


### Hosted Agent の outbound networking

Hosted Agent が外部公開済みのエンドポイントに到達できるかは、実行環境のネットワーク制約に依存します。安全な設計としては、直接 SSH や任意の遠隔コマンド実行を認めず、HTTP の read-only 確認だけを許可する形にします。

このリポジトリでは、直接接続が制限されているケースにも対応できるように、次の運用を採用しています。

- `HTTP_PROBE_ENDPOINT` を使った relay ベースの HTTP probe
- VM の公開 IP を環境変数や状態ファイルから解決
- コード内に固定 IP を埋め込まない

```bash
cp .env_sample .env

VM_PUBLIC_IP=$(grep '^VM_PUBLIC_IP=' .state/vm-nginx-404.env | cut -d= -f2-) && echo "VM_PUBLIC_IP=${VM_PUBLIC_IP}"
curl_result=`curl http://${VM_PUBLIC_IP}/health` && echo $curl_result

cd foundry-agent-demo
azd ai agent invoke "nginxを導入されたAzure VMにアクセスしました。アクセス先は http://${VM_PUBLIC_IP}/healthです。 curlでアクセスした結果は${curl_result} でした。ステータスコード、応答内容、原因候補を日本語で簡潔に示し、GitHub Copilot向けに修正のためのプロンプトを考えて生成してください。" --no-prompt
```

実際の接続方式は環境ごとに異なりますが、リポジトリの方針は一貫しています。Hosted Agent は診断と提案に限定し、修復や再読み込みは承認済みのローカル操作や安全な channel に委ねます。

### Hosted Agent を単体で実行する方法

Hosted Agent を直接呼ぶ場合は、エージェント定義がある [foundry-agent-demo/azure.yaml](foundry-agent-demo/azure.yaml) のディレクトリで実行してください。

この設計では、Agent は SSH で VM に接続せず、代わりに read-only の HTTP probe tool を使って公開 URL のステータスコードを確認します。確定的な許可操作は次のとおりです。

- `probe_http`：HTTP GET を実行して `status`, `body`, `url` を取得
- `get_nginx_service_status`：サービス状態の確認
- `get_nginx_access_log`：アクセスログの参照
- `get_nginx_error_log`：エラーログの参照
- `get_nginx_active_config`：現在の NGINX 設定の確認

このリポジトリで「Hosted Agent が直接 VM のパブリック IP へ HTTP を送る」場合、Hosted Agent の outbound networking を明示的に許可する必要があります。現在の実運用では、実行環境から外部公開 IP への直接接続は制限されているため、HTTP 接続の許可設定とネットワーク制約を確認してから利用してください。

```bash

VM_PUBLIC_IP=$(grep '^VM_PUBLIC_IP=' ../.state/vm-nginx-404.env | cut -d= -f2-)

azd ai agent show
azd ai agent invoke "VM 上の vm-nginx-404 を一次調査してください。対象は ${VM_PUBLIC_IP} で、URL は http://${VM_PUBLIC_IP}/health です。IP は実行時に渡す値で、コード内に固定しません。SSH や任意のシェル実行は行わず、HTTP probe とログ確認のみで 200 / 404 / timeout のどれかを判断し、原因候補と次に実施すべき安全な確認手順を日本語で簡潔にお願いします。" --no-prompt
```

以下は、より明確に運用向けにした日本語の invoke 例です。

```bash

VM_PUBLIC_IP=$(grep '^VM_PUBLIC_IP=' ../.state/vm-nginx-404.env | cut -d= -f2-)

azd ai agent invoke "これは一次調査です。対象 VM は ${VM_PUBLIC_IP} で、監視URLは http://${VM_PUBLIC_IP}/health です。HTTP のみで状態確認を行い、SSH、任意のシェル実行、設定変更はしないでください。まず現状のステータスコード、応答内容、ログに残っている異常の特徴を日本語で整理し、最も可能性が高い根本原因と次の安全な確認手順を提示してください。" --no-prompt
```

もしリポジトリ直下で `azd ai agent invoke` を実行すると、Hosted Agent の定義が見つからず、次のようなエラーになります。

```text
ERROR: could not resolve agent service in azd project: no azure.ai.agent service found in azure.yaml
```

### 一次調査（read-only）を Hosted Agent に依頼する方法

修復をせずに、まずは「原因候補と次に確認すべき証跡」を依頼するのが実運用上の安全な使い方です。以下の日本語のコマンド例を使ってください。

```bash

./scripts/break.sh vm-nginx-404
./scripts/verify.sh vm-nginx-404 broken

VM_PUBLIC_IP=$(grep '^VM_PUBLIC_IP=' .state/vm-nginx-404.env | cut -d= -f2-)


azd ai agent invoke "これは一次調査のみです。VM への修復やコマンド実行は行わず、VM で発生している 404 の原因候補と、次に確認すべき証跡を日本語で説明してください。対象は ${VM_PUBLIC_IP} で、URL は http://${VM_PUBLIC_IP}/health です。調査は読み取り専用で、変更や修復は行わず、HTTP 状態とログの観点だけで判断してください。" --no-prompt
```

この方法では、AI は次のような内容を返します。

- 404 の原因候補
- 確認すべきログと設定ファイル
- `nginx -t`, `nginx -T`, access log, error log, `curl` の確認観点
- その後にローカルまたは承認済みスクリプトで実行すべき修復手順

### Hosted Agent から Azure VM へ直接接続できるか

このリポジトリでの実運用では、Hosted Agent は Azure VM に対して直接 SSH を行い、任意のシェル操作を実行できません。一方で、Hosted Agent の outbound networking を許可した場合、run-time で受け取ったパブリック IP に対して HTTP GET を実行し、`status` と `body` を確認できます。

```text
No — I cannot directly SSH to the target Azure VM from this Hosted Agent context.
```

なお、実際の direct HTTP probe は次のような invoke で実行する設計です。IP はコードに固定せず、実行時に渡します。

```bash

VM_PUBLIC_IP=$(grep '^VM_PUBLIC_IP=' ../.state/vm-nginx-404.env | cut -d= -f2-)

azd ai agent invoke "これは一次調査のみです。対象は ${VM_PUBLIC_IP} で、URL は http://${VM_PUBLIC_IP}/health です。_probe_http ツールを使って疎通確認し、HTTP ステータスコードと応答内容を確認してください。SSH や修復、設定変更、再読み込みは行わず、read-only 調査のみです。IP は実行時の値を使い、コード中に固定しません。結果は日本語で、ステータス・HTTP応答・原因候補・次の確認事項をまとめてください。" --no-prompt
```

なぜなら、Hosted Agent は安全性のために次の制約を持つためです。

- サンドボックス化された実行環境
- 任意のアウトバウンド接続や SSH 実行は不可
- SSH の秘密鍵や資格情報を保持できない
- 顧客環境への直接アクセスを許可しない設計

実際にこの環境で live probe を実行した結果は次のとおりです。

```text
URL= http://20.106.237.102/health
STATUS= 503
BODY= probe_error: <urlopen error timed out>
```

これは「SSH ではなく、HTTP GET で live endpoint を見ている」ことを示す実証です。ただし、Hosted Agent の outbound networking が有効でない場合は `503 timeout` となり、ステータスコードそのものは取得できないことがあります。その場合は、Agent は「timeout で到達不能」と判断し、ローカル端末または承認済み channel で `curl` / `verify.sh` による確認を分離して実施します。

```bash
./scripts/remote-action-channel.sh repair vm-nginx-404
./scripts/verify.sh vm-nginx-404 healthy
```

この運用モデルでは、AI は「診断・ガイダンス」だけを担当し、実際の運用実行と検証はローカル側で安全に行います。

`VM_PUBLIC_IP` はデプロイ時に状態ファイルから取得する値であり、固定 IP ではありません。実際の公開 IP は次で確認できます。

```bash
source .state/vm-nginx-404.env
echo "$VM_PUBLIC_IP"
```

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
