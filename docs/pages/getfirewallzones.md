# List Firewall Zones

`GET /v1/sites/{siteId}/firewall/zones`  
operationId: `getFirewallZones`  

Retrieve a list of all firewall zones on a site.


**Filterable properties (click to expand):**



|Name|Type|Allowed functions|
|-|-|-|
|`id`|`UUID`|`eq` `ne` `in` `notIn`|
|`name`|`STRING`|`eq` `ne` `in` `notIn` `like`|
|`metadata.origin`|`STRING`|`eq` `ne` `in` `notIn`|
|`metadata.configurable`|`BOOLEAN`|`eq` `ne` `isNull` `isNotNull`|
