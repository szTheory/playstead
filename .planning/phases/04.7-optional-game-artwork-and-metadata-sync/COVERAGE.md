# API Coverage — IGDB v4

Official capability source: https://api-docs.igdb.com/ (endpoint navigation and request/reference sections, reviewed 2026-10-12). Full API surface is inventoried below; the phase deliberately integrates only game identity/presentation data needed for META-01. All other endpoints have a scope reason. Endpoint names use official navigation labels and ordinary snake_case path spelling; executor confirms exact paths from current docs before implementation. The Game endpoint supplies title, summary, platform, cover and screenshot references; Cover/Screenshot endpoints supply validated image IDs. No ROM-hash lookup is documented, so it is unsupported and must never silently fall back to filename/hash disclosure. CDN image serving remains conditional on exact private-serving terms; this does not block adapter implementation or private media.

| capability | decision | reason |
|---|---|---|
| POST /v4/age_rating | OPT-OUT | Outside title/system, description, cover and still-gallery phase; no unrelated catalogue or acquisition surface. |
| POST /v4/age_rating_category | OPT-OUT | Outside title/system, description, cover and still-gallery phase; no unrelated catalogue or acquisition surface. |
| POST /v4/age_rating_content_description | OPT-OUT | Outside title/system, description, cover and still-gallery phase; no unrelated catalogue or acquisition surface. |
| POST /v4/age_rating_content_description_type | OPT-OUT | Outside title/system, description, cover and still-gallery phase; no unrelated catalogue or acquisition surface. |
| POST /v4/age_rating_content_description_v2 | OPT-OUT | Outside title/system, description, cover and still-gallery phase; no unrelated catalogue or acquisition surface. |
| POST /v4/age_rating_organization | OPT-OUT | Outside title/system, description, cover and still-gallery phase; no unrelated catalogue or acquisition surface. |
| POST /v4/alternative_name | OPT-OUT | Outside title/system, description, cover and still-gallery phase; no unrelated catalogue or acquisition surface. |
| POST /v4/artwork | OPT-OUT | Outside title/system, description, cover and still-gallery phase; no unrelated catalogue or acquisition surface. |
| POST /v4/artwork_type | OPT-OUT | Outside title/system, description, cover and still-gallery phase; no unrelated catalogue or acquisition surface. |
| POST /v4/character | OPT-OUT | Outside title/system, description, cover and still-gallery phase; no unrelated catalogue or acquisition surface. |
| POST /v4/character_gender | OPT-OUT | Outside title/system, description, cover and still-gallery phase; no unrelated catalogue or acquisition surface. |
| POST /v4/character_mug_shot | OPT-OUT | Outside title/system, description, cover and still-gallery phase; no unrelated catalogue or acquisition surface. |
| POST /v4/character_species | OPT-OUT | Outside title/system, description, cover and still-gallery phase; no unrelated catalogue or acquisition surface. |
| POST /v4/collection | OPT-OUT | Outside title/system, description, cover and still-gallery phase; no unrelated catalogue or acquisition surface. |
| POST /v4/collection_membership | OPT-OUT | Outside title/system, description, cover and still-gallery phase; no unrelated catalogue or acquisition surface. |
| POST /v4/collection_membership_type | OPT-OUT | Outside title/system, description, cover and still-gallery phase; no unrelated catalogue or acquisition surface. |
| POST /v4/collection_relation | OPT-OUT | Outside title/system, description, cover and still-gallery phase; no unrelated catalogue or acquisition surface. |
| POST /v4/collection_relation_type | OPT-OUT | Outside title/system, description, cover and still-gallery phase; no unrelated catalogue or acquisition surface. |
| POST /v4/collection_type | OPT-OUT | Outside title/system, description, cover and still-gallery phase; no unrelated catalogue or acquisition surface. |
| POST /v4/company | OPT-OUT | Outside title/system, description, cover and still-gallery phase; no unrelated catalogue or acquisition surface. |
| POST /v4/company_logo | OPT-OUT | Outside title/system, description, cover and still-gallery phase; no unrelated catalogue or acquisition surface. |
| POST /v4/company_size | OPT-OUT | Outside title/system, description, cover and still-gallery phase; no unrelated catalogue or acquisition surface. |
| POST /v4/company_status | OPT-OUT | Outside title/system, description, cover and still-gallery phase; no unrelated catalogue or acquisition surface. |
| POST /v4/company_type | OPT-OUT | Outside title/system, description, cover and still-gallery phase; no unrelated catalogue or acquisition surface. |
| POST /v4/company_type_history | OPT-OUT | Outside title/system, description, cover and still-gallery phase; no unrelated catalogue or acquisition surface. |
| POST /v4/company_website | OPT-OUT | Outside title/system, description, cover and still-gallery phase; no unrelated catalogue or acquisition surface. |
| POST /v4/cover | INTEGRATE |  |
| POST /v4/date_format | OPT-OUT | Outside title/system, description, cover and still-gallery phase; no unrelated catalogue or acquisition surface. |
| POST /v4/entity_type | OPT-OUT | Outside title/system, description, cover and still-gallery phase; no unrelated catalogue or acquisition surface. |
| POST /v4/event | OPT-OUT | Outside title/system, description, cover and still-gallery phase; no unrelated catalogue or acquisition surface. |
| POST /v4/event_logo | OPT-OUT | Outside title/system, description, cover and still-gallery phase; no unrelated catalogue or acquisition surface. |
| POST /v4/event_network | OPT-OUT | Outside title/system, description, cover and still-gallery phase; no unrelated catalogue or acquisition surface. |
| POST /v4/executable | OPT-OUT | Outside title/system, description, cover and still-gallery phase; no unrelated catalogue or acquisition surface. |
| POST /v4/external_game | OPT-OUT | Outside title/system, description, cover and still-gallery phase; no unrelated catalogue or acquisition surface. |
| POST /v4/external_game_source | OPT-OUT | Outside title/system, description, cover and still-gallery phase; no unrelated catalogue or acquisition surface. |
| POST /v4/franchise | OPT-OUT | Outside title/system, description, cover and still-gallery phase; no unrelated catalogue or acquisition surface. |
| POST /v4/game | INTEGRATE |  |
| POST /v4/game_engine | OPT-OUT | Outside title/system, description, cover and still-gallery phase; no unrelated catalogue or acquisition surface. |
| POST /v4/game_engine_logo | OPT-OUT | Outside title/system, description, cover and still-gallery phase; no unrelated catalogue or acquisition surface. |
| POST /v4/game_localization | OPT-OUT | Outside title/system, description, cover and still-gallery phase; no unrelated catalogue or acquisition surface. |
| POST /v4/game_mode | OPT-OUT | Outside title/system, description, cover and still-gallery phase; no unrelated catalogue or acquisition surface. |
| POST /v4/game_release_format | OPT-OUT | Outside title/system, description, cover and still-gallery phase; no unrelated catalogue or acquisition surface. |
| POST /v4/game_status | OPT-OUT | Outside title/system, description, cover and still-gallery phase; no unrelated catalogue or acquisition surface. |
| POST /v4/game_time_to_beat | OPT-OUT | Outside title/system, description, cover and still-gallery phase; no unrelated catalogue or acquisition surface. |
| POST /v4/game_type | OPT-OUT | Outside title/system, description, cover and still-gallery phase; no unrelated catalogue or acquisition surface. |
| POST /v4/game_version | OPT-OUT | Outside title/system, description, cover and still-gallery phase; no unrelated catalogue or acquisition surface. |
| POST /v4/game_version_feature | OPT-OUT | Outside title/system, description, cover and still-gallery phase; no unrelated catalogue or acquisition surface. |
| POST /v4/game_version_feature_value | OPT-OUT | Outside title/system, description, cover and still-gallery phase; no unrelated catalogue or acquisition surface. |
| POST /v4/game_video | OPT-OUT | Outside title/system, description, cover and still-gallery phase; no unrelated catalogue or acquisition surface. |
| POST /v4/genre | OPT-OUT | Outside title/system, description, cover and still-gallery phase; no unrelated catalogue or acquisition surface. |
| POST /v4/image_type | OPT-OUT | Outside title/system, description, cover and still-gallery phase; no unrelated catalogue or acquisition surface. |
| POST /v4/keyword | OPT-OUT | Outside title/system, description, cover and still-gallery phase; no unrelated catalogue or acquisition surface. |
| POST /v4/involved_company | OPT-OUT | Outside title/system, description, cover and still-gallery phase; no unrelated catalogue or acquisition surface. |
| POST /v4/language | OPT-OUT | Outside title/system, description, cover and still-gallery phase; no unrelated catalogue or acquisition surface. |
| POST /v4/language_support | OPT-OUT | Outside title/system, description, cover and still-gallery phase; no unrelated catalogue or acquisition surface. |
| POST /v4/language_support_type | OPT-OUT | Outside title/system, description, cover and still-gallery phase; no unrelated catalogue or acquisition surface. |
| POST /v4/logo | OPT-OUT | Outside title/system, description, cover and still-gallery phase; no unrelated catalogue or acquisition surface. |
| POST /v4/multiplayer_mode | OPT-OUT | Outside title/system, description, cover and still-gallery phase; no unrelated catalogue or acquisition surface. |
| POST /v4/network_type | OPT-OUT | Outside title/system, description, cover and still-gallery phase; no unrelated catalogue or acquisition surface. |
| POST /v4/platform | INTEGRATE |  |
| POST /v4/platform_family | OPT-OUT | Outside title/system, description, cover and still-gallery phase; no unrelated catalogue or acquisition surface. |
| POST /v4/platform_logo | OPT-OUT | Outside title/system, description, cover and still-gallery phase; no unrelated catalogue or acquisition surface. |
| POST /v4/platform_type | OPT-OUT | Outside title/system, description, cover and still-gallery phase; no unrelated catalogue or acquisition surface. |
| POST /v4/platform_version | OPT-OUT | Outside title/system, description, cover and still-gallery phase; no unrelated catalogue or acquisition surface. |
| POST /v4/platform_version_company | OPT-OUT | Outside title/system, description, cover and still-gallery phase; no unrelated catalogue or acquisition surface. |
| POST /v4/platform_version_release_date | OPT-OUT | Outside title/system, description, cover and still-gallery phase; no unrelated catalogue or acquisition surface. |
| POST /v4/platform_website | OPT-OUT | Outside title/system, description, cover and still-gallery phase; no unrelated catalogue or acquisition surface. |
| POST /v4/player_perspective | OPT-OUT | Outside title/system, description, cover and still-gallery phase; no unrelated catalogue or acquisition surface. |
| POST /v4/popularity_primitive | OPT-OUT | Outside title/system, description, cover and still-gallery phase; no unrelated catalogue or acquisition surface. |
| POST /v4/popularity_type | OPT-OUT | Outside title/system, description, cover and still-gallery phase; no unrelated catalogue or acquisition surface. |
| POST /v4/region | OPT-OUT | Outside title/system, description, cover and still-gallery phase; no unrelated catalogue or acquisition surface. |
| POST /v4/release_date | OPT-OUT | Outside title/system, description, cover and still-gallery phase; no unrelated catalogue or acquisition surface. |
| POST /v4/release_date_region | OPT-OUT | Outside title/system, description, cover and still-gallery phase; no unrelated catalogue or acquisition surface. |
| POST /v4/release_date_status | OPT-OUT | Outside title/system, description, cover and still-gallery phase; no unrelated catalogue or acquisition surface. |
| POST /v4/report | OPT-OUT | Outside title/system, description, cover and still-gallery phase; no unrelated catalogue or acquisition surface. |
| POST /v4/report_type | OPT-OUT | Outside title/system, description, cover and still-gallery phase; no unrelated catalogue or acquisition surface. |
| POST /v4/screenshot | INTEGRATE |  |
| POST /v4/search | INTEGRATE |  |
| POST /v4/theme | OPT-OUT | Outside title/system, description, cover and still-gallery phase; no unrelated catalogue or acquisition surface. |
| POST /v4/website | OPT-OUT | Outside title/system, description, cover and still-gallery phase; no unrelated catalogue or acquisition surface. |
| POST /v4/website_type | OPT-OUT | Outside title/system, description, cover and still-gallery phase; no unrelated catalogue or acquisition surface. |
| POST /v4/{endpoint}/count | OPT-OUT | Selected-game lookup is bounded at ten candidates; collection-wide count/download is outside scope. |
| POST /v4/multiquery | OPT-OUT | Single selected-game requests make disclosure and rate accounting explicit. |
| IGDB image CDN fixed variant | INTEGRATE | Rights-gated private image retrieval only, from validated image ID and fixed host/size. |
| Webhooks | OPT-OUT | Optional on-demand private enrichment uses durable local jobs and refresh; external callback is unnecessary. |
| Data dumps | OPT-OUT | Whole catalogue ingestion violates selected-game/on-demand scope and privacy estimate. |
| PopScore | OPT-OUT | Popularity rankings do not identify or describe a private imported game. |
| IGDB MCP server | OPT-OUT | Runtime server adapter uses bounded API calls; no agent tool exposure required. |
| Twitch OAuth client credentials | INTEGRATE | Operator-supplied credentials only; server-side token flow, no shared Playstead credential. |

Credential and policy evidence: self-hoster supplies Twitch app credentials at runtime; the IGDB docs authorize API data caching but the reviewed public FAQ does not prove underlying third-party artwork sublicense or private serving grant. Live image fetch stays disabled until a recorded clause/written provider decision establishes the exact private serving right; a general counsel/UAT gate is not imposed on software closure. Metadata lookup and user-owned private originals remain available. No live calls during planning or tests.
