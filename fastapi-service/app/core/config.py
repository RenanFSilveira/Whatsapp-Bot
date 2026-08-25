from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    supabase_url: str = ""
    supabase_service_key: str = ""
    jwt_secret: str = "change-me-in-production"
    jwt_algorithm: str = "HS256"
    jwt_audience: str = "turbo-track"

    # Chatwoot
    chatwoot_url: str = ""
    chatwoot_api_token: str = ""
    chatwoot_account_id: int = 1

    # Evolution API (for outbound messages)
    evolution_api_url: str = ""
    evolution_api_key: str = ""

    # Forward incoming webhooks to this URL after processing (preserves existing n8n flow)
    webhook_forward_url: str = ""


settings = Settings()
