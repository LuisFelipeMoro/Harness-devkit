# Reference: Spec-Driven Development

## When it applies

Apply when architecture has **HTTP endpoints** (REST API, BFF, microservice with a public HTTP interface).
Skip for: pure internal libraries, CLI tools, background workers with no HTTP boundary.
Presence signal: `api-spec.yaml` exists in project root.

## The contract rule

**Spec is the source of truth. Code follows spec — not the other way around.**

- Spec written by Winston (Architect) BEFORE Amelia writes a single line
- Implementation must satisfy spec exactly: schemas, status codes, auth, error shapes
- Spec changes require updating `api-spec.yaml` first → then update code
- Annotations (swag, Springdoc, JSDoc) are verification that code matches spec — they do not define the spec
- Never fix spec drift by weakening the spec

---

## Workflow

```
Architect (Winston)
  └─ api-spec.yaml written (OpenAPI 3.1) — ALL endpoints, schemas, errors, auth
       ↓
Scrum Master (Bob)
  └─ story references operationId(s) from spec
       ↓
Coder — Backend (producer)
  └─ Phase 0 reads api-spec.yaml → implements to spec exactly; annotations match spec (not vice versa)
  └─ Then writes contract tests (status, schema, auth) and falsifies each by dropping a
     required field / changing the status — confirming the test catches spec drift
Coder — Frontend (consumer)
  └─ implements against the spec'd endpoints → then writes tests that mock them (msw/nock)
     and assert the UI handles every spec response (success + each error shape), falsifying
     each by returning a different status or a missing field
  └─ the api-spec is the shared contract between the two coders — neither invents shapes
       ↓
QA (Quinn)
  └─ Audits the contract tests exist per operationId AND carry falsification evidence (else QA→CODER TEST GAP)
  └─ Spectral lint: spec quality gate · Schema validation: response shapes match spec
       ↓
Reviewer
  └─ Spec drift check: annotations ↔ spec ↔ implementation alignment
```

---

## api-spec.yaml format (OpenAPI 3.1)

Minimal complete template — Winston fills every field:

```yaml
openapi: "3.1.0"
info:
  title: "{Feature Name} API"
  version: "1.0.0"
paths:
  /resource:
    post:
      operationId: createResource
      summary: Create a resource
      tags: [resource]
      security:
        - bearerAuth: []
      requestBody:
        required: true
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/CreateResourceRequest'
      responses:
        "201":
          description: Created
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/ResourceResponse'
        "400":
          $ref: '#/components/responses/ValidationError'
        "401":
          $ref: '#/components/responses/Unauthorized'
        "409":
          $ref: '#/components/responses/Conflict'
        "500":
          $ref: '#/components/responses/InternalError'

components:
  securitySchemes:
    bearerAuth:
      type: http
      scheme: bearer
      bearerFormat: JWT

  schemas:
    CreateResourceRequest:
      type: object
      required: [field1, field2]
      properties:
        field1:
          type: string
          minLength: 1
          maxLength: 255
        field2:
          type: integer
          minimum: 0

    ResourceResponse:
      type: object
      required: [id, field1, field2, createdAt]
      properties:
        id:
          type: string
          format: uuid
        field1:
          type: string
        field2:
          type: integer
        createdAt:
          type: string
          format: date-time

    ErrorResponse:
      type: object
      required: [error, message, request_id]
      properties:
        error:
          type: string
        message:
          type: string
        request_id:
          type: string
          format: uuid

  responses:
    ValidationError:
      description: Input validation failed
      content:
        application/json:
          schema:
            $ref: '#/components/schemas/ErrorResponse'
    Unauthorized:
      description: Missing or invalid auth token
      content:
        application/json:
          schema:
            $ref: '#/components/schemas/ErrorResponse'
    Conflict:
      description: Resource already exists
      content:
        application/json:
          schema:
            $ref: '#/components/schemas/ErrorResponse'
    InternalError:
      description: Unexpected server error
      content:
        application/json:
          schema:
            $ref: '#/components/schemas/ErrorResponse'
```

**Rules for Winston:**
- Every endpoint gets an `operationId` (camelCase verb+noun: `createResource`, `getCart`, `deleteSession`)
- Every `4xx`/`5xx` response typed — never bare `description: Error`
- All request/response schemas under `components/schemas` — never inline in path
- `required` arrays on every object schema — no optional fields unless explicitly optional in PRD
- Auth: every protected endpoint has `security` field; public endpoints explicitly `security: []`

---

## .spectral.yaml (place in project root)

```yaml
extends: ["spectral:oas"]
rules:
  operation-operationId: error        # every operation must have operationId
  operation-summary: error            # every operation must have summary
  operation-tags: warn                # tag every operation for grouping
  oas3-valid-media-example: error     # examples must be schema-valid
  no-$ref-siblings: error             # no fields alongside $ref
  oas3-unused-component: warn         # warn on orphaned components
  info-contact: off                   # not required for internal APIs
```

---

## Quality gates

| Gate | Command | When |
|------|---------|------|
| Spec lint | `rtk npx @stoplight/spectral-cli lint api-spec.yaml --ruleset .spectral.yaml` | Always (if api-spec.yaml exists) |
| Spec validate | `rtk npx swagger-cli validate api-spec.yaml` | Always |
| Contract test | `rtk schemathesis run api-spec.yaml --url http://localhost:{port} --checks all` | Integration only (running server) |

---

## Code generation (optional — use when spec is stable)

| Language | Tool | Command |
|----------|------|---------|
| Go | oapi-codegen | `oapi-codegen -package api -generate types,server api-spec.yaml > internal/api/spec_gen.go` |
| TypeScript | openapi-typescript | `npx openapi-typescript api-spec.yaml -o src/types/api.gen.ts` |
| Java (Spring) | openapi-generator | `openapi-generator generate -i api-spec.yaml -g spring -o src/main/generated` |

Generated files are **read-only** — never edit directly. Prefix with `_gen` or `gen_` to mark. Regenerate on spec change.

---

## Annotation alignment (code must match spec — not vice versa)

### Go — swaggo/swag

Annotations must reproduce the spec operationId, all status codes, and all schema refs:

```go
// @Summary     Create resource
// @Description Creates a new resource. Idempotency-Key header required.
// @Tags        resource
// @Accept      json
// @Produce     json
// @Security    BearerAuth
// @Param       request body CreateResourceRequest true "Request body"
// @Success     201 {object} ResourceResponse
// @Failure     400 {object} ErrorResponse "Validation failed"
// @Failure     401 {object} ErrorResponse "Unauthorized"
// @Failure     409 {object} ErrorResponse "Already exists"
// @Failure     500 {object} ErrorResponse "Internal error"
// @Router      /resource [post]
```

Run `rtk swag init ./...` — must compile zero errors. Stale annotation = MAJOR reviewer finding.

### Java — Springdoc

```java
@Operation(operationId = "createResource", summary = "Create a resource", tags = {"resource"})
@ApiResponses({
    @ApiResponse(responseCode = "201", description = "Created",
        content = @Content(schema = @Schema(implementation = ResourceResponse.class))),
    @ApiResponse(responseCode = "400", description = "Validation failed",
        content = @Content(schema = @Schema(implementation = ErrorResponse.class))),
    @ApiResponse(responseCode = "401", description = "Unauthorized",
        content = @Content(schema = @Schema(implementation = ErrorResponse.class)))
})
```

### TypeScript / NestJS

```typescript
@ApiOperation({ operationId: 'createResource', summary: 'Create a resource' })
@ApiCreatedResponse({ type: ResourceResponse })
@ApiBadRequestResponse({ type: ErrorResponse })
@ApiUnauthorizedResponse({ type: ErrorResponse })
```

### TypeScript / Express + JSDoc

```typescript
/**
 * @swagger
 * /resource:
 *   post:
 *     operationId: createResource
 *     summary: Create a resource
 *     tags: [resource]
 *     security:
 *       - bearerAuth: []
 *     requestBody:
 *       required: true
 *       content:
 *         application/json:
 *           schema:
 *             $ref: '#/components/schemas/CreateResourceRequest'
 *     responses:
 *       201:
 *         description: Created
 *         content:
 *           application/json:
 *             schema:
 *               $ref: '#/components/schemas/ResourceResponse'
 *       400:
 *         $ref: '#/components/responses/ValidationError'
 */
```

---

## Spec drift detection

| Symptom | Root cause | Fix |
|---------|-----------|-----|
| Spectral finds missing operationId | Annotation incomplete | Update annotation to match spec |
| Response field in code not in spec schema | Implementation drift | Either add field to spec first (Architect approval) or remove from code |
| Status code in code not in spec | Missing error path in spec | Add to spec first, then implement |
| Annotation references a type not in spec components | Code-first drift | Add schema to spec; update annotation to use $ref |
| `schemathesis` fails on a valid request | Implementation doesn't honour schema | Fix handler validation logic |

---

## Contract testing with Schemathesis (integration phase)

```bash
# Start app in test mode (use TEST_DB, no rate limiting)
export APP_PORT=8080
./app --env=test &

schemathesis run api-spec.yaml \
  --url http://localhost:8080 \
  --checks all \
  --validate-schema true \
  --hypothesis-max-examples 100 \
  --auth-type bearer \
  --auth "$TEST_JWT_TOKEN"
```

Schemathesis generates adversarial inputs from schema constraints. Every `schemathesis` failure = spec drift or missing input validation.
