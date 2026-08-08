# List VPN Servers

`GET /v1/sites/{siteId}/vpn/servers`  
operationId: `getVpnServerPage`  

Retrieve a paginated list of all VPN servers on a site.


**Filterable properties (click to expand):**



|Name|Type|Allowed functions|
|-|-|-|
|`type`|`STRING`|`eq` `ne` `in` `notIn`|
|`id`|`UUID`|`eq` `ne` `in` `notIn`|
|`name`|`STRING`|`eq` `ne` `in` `notIn` `like`|
|`enabled`|`BOOLEAN`|`eq` `ne`|
|`metadata.origin`|`STRING`|`eq` `ne` `in` `notIn`|
