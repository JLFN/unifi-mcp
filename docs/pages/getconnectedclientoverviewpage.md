# List Connected Clients

`GET /v1/sites/{siteId}/clients`  
operationId: `getConnectedClientOverviewPage`  

Retrieve a paginated list of all connected clients on a site, including physical devices (computers, smartphones) and active VPN connections.


**Filterable properties (click to expand):**



|Name|Type|Allowed functions|
|-|-|-|
|`id`|`UUID`|`eq` `ne` `in` `notIn`|
|`type`|`STRING`|`eq` `ne` `in` `notIn`|
|`macAddress`|`STRING`|`isNull` `isNotNull` `eq` `ne` `in` `notIn`|
|`ipAddress`|`STRING`|`isNull` `isNotNull` `eq` `ne` `in` `notIn`|
|`connectedAt`|`TIMESTAMP`|`isNull` `isNotNull` `eq` `ne` `gt` `ge` `lt` `le`|
|`access.type`|`STRING`|`eq` `ne` `in` `notIn`|
|`access.authorized`|`BOOLEAN`|`isNull` `isNotNull` `eq` `ne`|
