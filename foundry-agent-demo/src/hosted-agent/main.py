import asyncio
import os

from agent_framework import Agent
from agent_framework.foundry import FoundryChatClient
from agent_framework_foundry_hosting import ResponsesHostServer
from azure.identity import DefaultAzureCredential
from dotenv import load_dotenv

load_dotenv()


async def main() -> None:
    model_name = os.getenv("AZURE_AI_MODEL_DEPLOYMENT_NAME") or os.getenv("FOUNDRY_MODEL_NAME")
    if not model_name:
        raise RuntimeError(
            "Model deployment name is not configured. Set AZURE_AI_MODEL_DEPLOYMENT_NAME or FOUNDRY_MODEL_NAME."
        )

    project_endpoint = os.environ.get("FOUNDRY_PROJECT_ENDPOINT")
    if not project_endpoint:
        raise RuntimeError("FOUNDRY_PROJECT_ENDPOINT is required for the hosted agent runtime.")

    client = FoundryChatClient(
        project_endpoint=project_endpoint,
        model=model_name,
        credential=DefaultAzureCredential(),
    )

    agent = Agent(
        client=client,
        instructions=(
            "You are a deterministic incident-response agent for the vm-nginx-404 workload. "
            "Investigate the HTTP 404 evidence, identify the most likely root cause, perform only safe "
            "and allowed remediation, validate recovery, and confirm the final HTTP status. "
            "Keep the response concise, structured, and operationally oriented."
        ),
        default_options={"store": False},
    )

    server = ResponsesHostServer(agent)
    await server.run_async()


if __name__ == "__main__":
    asyncio.run(main())
