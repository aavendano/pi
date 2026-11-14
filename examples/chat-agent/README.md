# chat-agent

A conversational agent built with the [Mistral Agents SDK](https://docs.mistral.ai/studio/agents/getting-started/quickstart) (`from mistralai import agents`). The agent is in `main.py`.

It is designed for multi-turn chat: instructions keep replies short, warm, and context-aware within a session, and it exposes one tool, `get_current_time` (uses `agents.now()`, so it is safe under workflow replay on a managed worker).

Set `MISTRAL_API_KEY` in `.env` (key from [API keys](https://console.mistral.ai/api-keys)) — `.env` is git-ignored. Then:

```bash
uv run --env-file .env agents info                  # show what the CLI loads
uv run --env-file .env python main.py                # two-turn session demo, local
uv run --env-file .env agents chat                   # chat with the agent in this process
uv run --env-file .env agents deploy                 # deploy as a managed agent
```

Once deployed, chat with it by name and keep the conversation in one session:

```bash
uv run --env-file .env agents chat chat-agent
```

Or from code, explicitly multi-turn:

```python
import asyncio
from mistralai import agents

async def main() -> None:
    agent = agents.Agent.load_from(agent_name="chat-agent")
    session = await agent.start_session()
    state = await session.run("Hi! Who are you?")
    print(state.text)
    state = await session.run("And what time is it?")
    print(state.text)
    await session.cancel()

asyncio.run(main())
```

`agents deploy` builds the commit you pushed: the project must be in a GitHub repository, and the GitHub Connector must be enabled on your Mistral account in Studio.
