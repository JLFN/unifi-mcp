# List Firewall Policies

`GET /v1/sites/{siteId}/firewall/policies`  
operationId: `getFirewallPolicies`  

Retrieve a list of all firewall policies on a site.


**Filterable properties (click to expand):**



|Name|Type|Allowed functions|
|-|-|-|
|`id`|`UUID`|`eq` `ne` `in` `notIn`|
|`name`|`STRING`|`eq` `ne` `in` `notIn` `like`|
|`source.zoneId`|`UUID`|`eq` `ne` `in` `notIn`|
|`destination.zoneId`|`UUID`|`eq` `ne` `in` `notIn`|
|`metadata.origin`|`STRING`|`eq` `ne` `in` `notIn`|
