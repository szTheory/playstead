defmodule PlaysteadWeb.Api.V1.MetadataOpenAPI do
  @moduledoc "Additive OpenAPI contract for the existing versioned Phoenix API."

  def document do
    %{
      :"x-examples" => examples(),
      openapi: "3.1.0",
      info: %{title: "Playstead API", version: "1.1.0"},
      paths: %{
        "/api/v1/metadata/{asset_set_id}" => %{
          parameters: [
            %{
              name: "asset_set_id",
              in: "path",
              required: true,
              schema: %{type: "string", format: "uuid"}
            }
          ],
          get: %{
            operationId: "getMetadataSelection",
            security: [%{DeviceBearer: []}],
            responses: %{"200" => response("MetadataSelection"), "404" => response("Problem")}
          },
          post: %{
            operationId: "selectMetadataField",
            security: [%{DeviceBearer: []}],
            parameters: [
              %{name: "Idempotency-Key", in: "header", required: true, schema: %{type: "string"}}
            ],
            requestBody: json_body("MetadataSelectionRequest"),
            responses: %{
              "201" => response("MetadataSelection"),
              "409" => response("MetadataConflict"),
              "422" => response("Problem")
            }
          }
        },
        "/api/v1/metadata/{asset_set_id}/reset-provider" => %{
          post: %{
            operationId: "resetMetadataFieldToProviderEvidence",
            security: [%{DeviceBearer: []}],
            parameters: [
              %{name: "Idempotency-Key", in: "header", required: true, schema: %{type: "string"}}
            ],
            requestBody: json_body("ProviderResetRequest"),
            responses: %{
              "201" => response("MetadataSelection"),
              "409" => response("MetadataConflict")
            }
          }
        },
        "/api/v1/metadata/{asset_set_id}/media" => %{
          post: %{
            operationId: "uploadPrivateMetadataMedia",
            security: [%{DeviceBearer: []}],
            parameters: [
              %{
                name: "asset_set_id",
                in: "path",
                required: true,
                schema: %{type: "string", format: "uuid"}
              },
              %{name: "Idempotency-Key", in: "header", required: true, schema: %{type: "string"}},
              %{name: "Repr-Digest", in: "header", required: true, schema: %{type: "string"}},
              %{
                name: "Content-Length",
                in: "header",
                required: true,
                schema: %{type: "integer", minimum: 1}
              }
            ],
            requestBody: %{
              required: true,
              content: %{
                "image/png" => %{schema: %{type: "string", format: "binary"}},
                "image/jpeg" => %{schema: %{type: "string", format: "binary"}},
                "text/plain" => %{schema: %{type: "string", format: "binary"}}
              }
            },
            responses: %{"201" => %{description: "Original media recorded with provenance"}}
          }
        },
        "/api/v1/metadata/{asset_set_id}/media/{media_id}/original" => %{
          get: %{
            operationId: "getPrivateMetadataOriginal",
            security: [%{DeviceBearer: []}],
            responses: %{"200" => %{description: "Owner-scoped exact original bytes"}}
          }
        },
        "/api/v1/metadata/{asset_set_id}/provider" => %{
          get: %{
            operationId: "previewProviderConsent",
            security: [%{DeviceBearer: []}],
            responses: %{"200" => %{description: "Exact disclosure and provider readiness"}}
          }
        },
        "/api/v1/metadata/{asset_set_id}/provider/consent" => %{
          post: %{
            operationId: "enableProviderConsent",
            security: [%{DeviceBearer: []}],
            parameters: [
              %{name: "Idempotency-Key", in: "header", required: true, schema: %{type: "string"}}
            ],
            requestBody: json_body("ProviderConsentRequest"),
            responses: %{"200" => %{description: "Disclosure consent enabled"}}
          },
          delete: %{
            operationId: "revokeProviderConsent",
            security: [%{DeviceBearer: []}],
            parameters: [
              %{name: "Idempotency-Key", in: "header", required: true, schema: %{type: "string"}}
            ],
            responses: %{
              "200" => %{
                description: "Disclosure consent revoked; cache cleanup may be pending",
                content: %{
                  "application/json" => %{
                    schema: %{"$ref" => "#/components/schemas/ProviderConsentRevocationResponse"},
                    examples: %{
                      clean: %{value: examples().provider_consent_revocation_response},
                      cleanup_pending: %{
                        value: examples().provider_consent_revocation_partial_response
                      }
                    }
                  }
                }
              }
            }
          }
        },
        "/api/v1/metadata/{asset_set_id}/provider/search" => %{
          post: %{
            operationId: "searchProviderEvidence",
            security: [%{DeviceBearer: []}],
            parameters: [
              %{name: "Idempotency-Key", in: "header", required: true, schema: %{type: "string"}}
            ],
            responses: %{"200" => %{description: "Attributed suggestion evidence"}}
          }
        },
        "/api/v1/metadata/provider/enrichment/estimate" => %{
          post: %{
            operationId: "estimateProviderPreparation",
            security: [%{DeviceBearer: []}],
            requestBody: json_body("PreparationEstimateRequest"),
            responses: %{"200" => %{description: "Bounded preparation estimate"}}
          }
        },
        "/api/v1/metadata/{asset_set_id}/provider/enrichment" => %{
          post: %{
            operationId: "prepareProviderMetadata",
            security: [%{DeviceBearer: []}],
            parameters: [
              %{name: "Idempotency-Key", in: "header", required: true, schema: %{type: "string"}}
            ],
            requestBody: json_body("PreparationRequest"),
            responses: %{"202" => %{description: "Durable preparation job accepted"}}
          }
        },
        "/api/v1/metadata/provider/enrichment/{job_id}" => %{
          get: %{
            operationId: "getProviderPreparation",
            security: [%{DeviceBearer: []}],
            responses: %{"200" => %{description: "Durable preparation status"}}
          }
        },
        "/api/v1/changes" => %{
          get: %{
            operationId: "getChanges",
            responses: %{"200" => %{description: "Cursor journal page"}}
          }
        },
        "/api/v1/snapshot" => %{
          get: %{
            operationId: "getSnapshot",
            responses: %{"200" => %{description: "Snapshot and matching cursor"}}
          }
        },
        "/api/v1/capabilities" => %{
          get: %{
            operationId: "getCapabilities",
            responses: %{"200" => %{description: "Optional client capabilities"}}
          }
        }
      },
      components: %{
        securitySchemes: %{
          DeviceBearer: %{type: "http", scheme: "bearer"}
        },
        schemas: %{
          MetadataSelectionRequest: %{
            type: "object",
            required: ["field", "value", "base_revision"],
            properties: %{
              field: %{
                type: "string",
                enum: ["title", "description", "candidate", "cover", "screenshots"]
              },
              value: %{},
              base_revision: %{type: "integer", minimum: 0}
            }
          },
          ProviderResetRequest: %{
            type: "object",
            required: ["field", "base_revision", "evidence_id"],
            properties: %{
              field: %{
                type: "string",
                enum: ["title", "description", "candidate", "cover", "screenshots"]
              },
              base_revision: %{type: "integer", minimum: 0},
              evidence_id: %{type: "string", format: "uuid"}
            }
          },
          ProviderConsentRequest: %{
            type: "object",
            required: ["title", "system", "disclosure_revision"],
            properties: %{
              title: %{type: "string"},
              system: %{type: "string"},
              disclosure_revision: %{type: "string"}
            }
          },
          ProviderConsentRevocationResponse: %{
            type: "object",
            required: ["enabled", "revision"],
            properties: %{
              provider: %{type: "string", enum: ["igdb"]},
              enabled: %{type: "boolean", enum: [false]},
              revision: %{type: "integer", minimum: 0},
              cache_cleanup: %{
                type: "object",
                required: ["status", "retryable"],
                properties: %{
                  status: %{type: "string", enum: ["failed"]},
                  retryable: %{type: "boolean", enum: [true]}
                }
              }
            }
          },
          PreparationEstimateRequest: %{
            type: "object",
            required: ["selected_asset_set_ids"],
            properties: %{
              selected_asset_set_ids: %{type: "array", items: %{type: "string", format: "uuid"}}
            }
          },
          PreparationRequest: %{
            type: "object",
            required: ["mode", "estimate"],
            properties: %{
              mode: %{type: "string", enum: ["prepare"]},
              selected_asset_set_ids: %{type: "array", items: %{type: "string", format: "uuid"}},
              estimate: %{type: "object"}
            }
          },
          MetadataSelection: %{
            type: "object",
            required: [
              "asset_set_id",
              "description",
              "revision",
              "selections",
              "field_revisions",
              "field_sources",
              "deleted_fields",
              "conflicts",
              "evidence"
            ],
            properties: %{
              asset_set_id: %{type: "string", format: "uuid"},
              description: %{type: "string"},
              revision: %{type: "integer"},
              selections: %{type: "object", additionalProperties: true},
              field_revisions: %{type: "object", additionalProperties: %{type: "integer"}},
              field_sources: %{type: "object", additionalProperties: true},
              deleted_fields: %{type: "object", additionalProperties: %{type: "integer"}},
              conflicts: %{
                type: "array",
                items: %{"$ref" => "#/components/schemas/MetadataConflict"}
              },
              evidence: %{type: "object", additionalProperties: %{type: "object"}}
            }
          },
          MetadataConflict: %{
            type: "object",
            required: [
              "field",
              "base_revision",
              "current_revision",
              "current_alternative",
              "incoming_alternative"
            ],
            properties: %{
              field: %{type: "string"},
              base_revision: %{type: "integer"},
              current_revision: %{type: "integer"},
              current_alternative: %{type: "object"},
              incoming_alternative: %{type: "object"}
            }
          },
          Problem: %{type: "object", required: ["type", "title", "status"]}
        }
      }
    }
  end

  def examples do
    %{
      selection_request: %{field: "title", value: "Owner corrected title", base_revision: 0},
      selection_response: %{
        asset_set_id: "00000000-0000-4000-8000-000000000001",
        description: "",
        revision: 1,
        selections: %{title: "Owner corrected title"},
        field_revisions: %{title: 1},
        field_sources: %{title: %{source: "user"}},
        deleted_fields: %{},
        conflicts: [],
        evidence: %{}
      },
      conflict_response: %{
        type: "metadata_conflict",
        field: "title",
        base_revision: 0,
        current_revision: 1,
        current_alternative: %{value: "First title", revision: 1},
        incoming_alternative: %{value: "Second title", source: %{source: "user"}}
      },
      private_media_request: %{
        content_type: "image/png",
        provenance: %{source: "user_upload", validated: true}
      },
      private_media_response: %{
        id: "00000000-0000-4000-8000-000000000003",
        asset_set_id: "00000000-0000-4000-8000-000000000001",
        original_sha256: String.duplicate("a", 64),
        original_size_bytes: 128,
        original_mime: "image/png",
        derived_sha256: nil,
        derived_size_bytes: nil
      },
      provider_consent_request: %{
        title: "Owner supplied title",
        system: "gba",
        disclosure_revision: "igdb-title-system-v1"
      },
      provider_consent_response: %{
        provider: "igdb",
        enabled: true,
        revision: 1,
        disclosure_revision: "igdb-title-system-v1"
      },
      provider_consent_revocation_response: %{provider: "igdb", enabled: false, revision: 2},
      provider_consent_revocation_partial_response: %{
        provider: "igdb",
        enabled: false,
        revision: 2,
        cache_cleanup: %{status: "failed", retryable: true}
      },
      preparation_estimate_request: %{
        selected_asset_set_ids: ["00000000-0000-4000-8000-000000000001"]
      },
      preparation_request: %{
        mode: "prepare",
        selected_asset_set_ids: ["00000000-0000-4000-8000-000000000001"],
        estimate: %{requests: 1, bytes: 0}
      },
      preparation_response: %{
        jobs: [%{id: "00000000-0000-4000-8000-000000000004", state: "queued"}],
        estimate: %{requests: 1, bytes: 0, storage: 0}
      },
      capability_response: %{
        protocol: %{major: 1, minor: 0},
        server_build: "0.1.0",
        supported_client_ranges: %{
          protocol: %{min: "1.0.0", max: "1.0.0"},
          app: %{min: "1.0.0", max: "1.1.0"},
          cache: %{min: "1.0.0", max: "1.1.0"},
          transfer: %{min: "1.0.0", max: "1.1.0"},
          adapter: %{min: "1.0.0", max: "1.0.0"},
          save: %{min: "1.0.0", max: "1.0.0"}
        }
      },
      change_response: %{
        seq: 1,
        entity_kind: "metadata",
        entity_id: "00000000-0000-4000-8000-000000000001",
        operation: "upsert",
        payload: %{
          version: 1,
          type: "description",
          asset_set_id: "00000000-0000-4000-8000-000000000001",
          description: "Owner authored private description",
          revision: 1,
          deleted_at: nil,
          selections: %{description: "Owner authored private description"},
          field_revisions: %{description: 1},
          field_sources: %{description: %{source: "user"}},
          deleted_fields: %{},
          conflicts: [],
          evidence: %{}
        }
      },
      snapshot_response: %{
        entries: [],
        cursor: "opaque-cursor",
        has_more: false,
        next_after_id: nil,
        catalogue: [],
        job: [],
        curation: [],
        save: [],
        metadata: []
      }
    }
  end

  defp response(schema),
    do: %{
      description: "API response",
      content: %{"application/json" => %{schema: %{"$ref" => "#/components/schemas/#{schema}"}}}
    }

  defp json_body(schema),
    do: %{
      required: true,
      content: %{"application/json" => %{schema: %{"$ref" => "#/components/schemas/#{schema}"}}}
    }
end
