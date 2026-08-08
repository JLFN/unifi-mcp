# List Networks

`GET /v1/sites/{siteId}/networks`  
operationId: `getNetworksOverviewPage`  

Retrieve a paginated list of all Networks on a site.


**Filterable properties (click to expand):**



|Name|Type|Allowed functions|
|-|-|-|
|`management`|`STRING`|`eq` `ne` `in` `notIn`|
|`id`|`UUID`|`eq` `ne` `in` `notIn`|
|`name`|`STRING`|`eq` `ne` `in` `notIn` `like`|
|`enabled`|`BOOLEAN`|`eq` `ne`|
|`vlanId`|`INTEGER`|`eq` `ne` `gt` `ge` `lt` `le` `in` `notIn`|
|`deviceId`|`UUID`|`eq` `ne` `in` `notIn` `isNull` `isNotNull`|
|`metadata.origin`|`STRING`|`eq` `ne` `in` `notIn`|
