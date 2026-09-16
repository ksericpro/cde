I want kong gw to privide data for external to consume. Updating Digital Twins, theese are reconcil apis, which means the frontend will call at regular interval to refresh the count. At the same it will subscribe to some topic via websocket or sseevents or grpc. How can Kong support all this?

# Reconcil APIs:

- Get all sites: {{BACKEND_API}}/api/visualization/hierarchy

- Get Site Tree: {{BACKEND_API}}/api/visualization/hierarchy?siteName=SOV%20%40%2038ALT&tree=true

- Get Incident of Site Name with Period and Page Limit: {{BACKEND_API}}/api/visualization/incidents?siteName=SOV%20%40%2038ALT&daysBack=365&page=1&limit=30

- Get Site Tree with Site ID: {{BACKEND_API}}/api/visualization/hierarchy?siteId=6a9a86656ef76c2f8b374dd7

# real time updates

Additionally, the digital twin should be able to subscribe to a websocket or sse events to receive real time data updates.

The Postman Collection and environment are in ths folder:

- iMops-List (Vizzio).postman_collection.json
- iMops-Lite (Taylor).postman_environment.json

Please analyze and give me the implementation plan.
