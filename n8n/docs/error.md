Webhook execution failed before a response was sent
The service was not able to process your request
500 - "{\"success\":false,\"error\":\"Invalid credentials\",\"message\":\"Invalid credentials\"}"
AxiosError: Request failed with status code 500
at settle (/usr/local/lib/node*modules/n8n/node_modules/.pnpm/axios@1.18.0_patch_hash=149e256a2a7b632497650b32816716ced972ab02a5ab00fbd8a5158a51722c4_437e4fafb503be805d1d0ae72f0b0deb/node_modules/axios/dist/node/axios.cjs:2199:12)
at RedirectableRequest.handleResponse (/usr/local/lib/node_modules/n8n/node_modules/.pnpm/axios@1.18.0_patch_hash=149e256a2a7b632497650b32816716ced972ab02a5ab00fbd8a5158a51722c4_437e4fafb503be805d1d0ae72f0b0deb/node_modules/axios/dist/node/axios.cjs:3965:9)
at RedirectableRequest.emit (node:events:526:24)
at RedirectableRequest.\_processResponse (/usr/local/lib/node_modules/n8n/node_modules/.pnpm/follow-redirects@1.16.0_debug@4.4.3_supports-color@8.1.1*/node*modules/follow-redirects/index.js:424:10)
at ClientRequest.RedirectableRequest.\_onNativeResponse (/usr/local/lib/node_modules/n8n/node_modules/.pnpm/follow-redirects@1.16.0_debug@4.4.3_supports-color@8.1.1*/node_modules/follow-redirects/index.js:109:12)
at ClientRequest.wrapper (node:events:639:12)
at ClientRequest.emit (node:events:514:20)
at HTTPParser.parserOnIncomingClient (node:\_http_client:973:27)
at HTTPParser.parserOnHeadersComplete (node:\_http_common:125:17)
at Socket.socketOnData (node:\_http_client:808:22)
at Axios.request (/usr/local/lib/node_modules/n8n/node_modules/.pnpm/axios@1.18.0_patch_hash=149e256a2a7b632497650b32816716ced972ab02a5ab00fbd8a5158a51722c4_437e4fafb503be805d1d0ae72f0b0deb/node_modules/axios/dist/node/axios.cjs:5427:41)
at processTicksAndRejections (node:internal/process/task_queues:104:5)
at invokeAxios (/usr/local/lib/node_modules/n8n/node_modules/.pnpm/@n8n+backend-network@file++++home+runner+\_work+n8n+n8n+packages+@n8n+backend-network/node_modules/@n8n/backend-network/src/http/axios/invoke.ts:15:10)
at executeLegacyRequest (/usr/local/lib/node_modules/n8n/node_modules/.pnpm/@n8n+backend-network@file++++home+runner+\_work+n8n+n8n+packages+@n8n+backend-network/node_modules/@n8n/backend-network/src/http/legacy-request.ts:83:6)
at Object.requestLegacy (/usr/local/lib/node_modules/n8n/node_modules/.pnpm/@n8n+backend-network@file++++home+runner+\_work+n8n+n8n+packages+@n8n+backend-network/node_modules/@n8n/backend-network/src/http/outbound-http.ts:213:13)
at proxyRequestToAxios (/usr/local/lib/node_modules/n8n/node_modules/.pnpm/n8n-core@file++++home+runner+\_work+n8n+n8n+packages+core/node_modules/n8n-core/src/execution-engine/node-execution-context/utils/request-helpers/legacy-request-adapter.ts:27:9)
at Object.request (/usr/local/lib/node_modules/n8n/node_modules/.pnpm/n8n-core@file++++home+runner+\_work+n8n+n8n+packages+core/node_modules/n8n-core/src/execution-engine/node-execution-context/utils/request-helpers/factory.ts:167:11)

Webhook execution failed before a response was sent

# solutions

user = proscalar@gmail.com
password = fwpkyjcf2i8fcoP05yEz

This should be used for Kong API webhook:
1. Kong API Webhook calls n8n webhook URL with the user and password (`proscalar@gmail.com:fwpkyjcf2i8fcoP05yEz`)
2. n8n webhook calls upstream iMOPS API with the same user and password (`proscalar@gmail.com:fwpkyjcf2i8fcoP05yEz`)

Environment Variables configured in n8n (`.env`, `docker-compose.yml`, and `workflows/proscalar_ingestion_workflow.json`):
- `PROSCALAR_TO_IMOPS_API=http://host.docker.internal:13000` (or `http://10.99.32.54:13000` in production)
- `PROSCALAR_TO_IMOPS_AUTH=Basic cHJvc2NhbGFyQGdtYWlsLmNvbTpmd3BreWpjZjJpOGZjb1AwNXlFeg==`
- `BACKEND_API` is kept as a backward-compatibility fallback.
