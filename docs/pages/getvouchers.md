# List Vouchers

`GET /v1/sites/{siteId}/hotspot/vouchers`  
operationId: `getVouchers`  

Retrieve a paginated list of Hotspot vouchers.


**Filterable properties (click to expand):**



|Name|Type|Allowed functions|
|-|-|-|
|`id`|`UUID`|`eq` `ne` `in` `notIn`|
|`createdAt`|`TIMESTAMP`|`eq` `ne` `gt` `ge` `lt` `le`|
|`name`|`STRING`|`eq` `ne` `in` `notIn` `like`|
|`code`|`STRING`|`eq` `ne` `in` `notIn`|
|`authorizedGuestLimit`|`INTEGER`|`isNull` `isNotNull` `eq` `ne` `gt` `ge` `lt` `le`|
|`authorizedGuestCount`|`INTEGER`|`eq` `ne` `gt` `ge` `lt` `le`|
|`activatedAt`|`TIMESTAMP`|`eq` `ne` `gt` `ge` `lt` `le`|
|`expiresAt`|`TIMESTAMP`|`eq` `ne` `gt` `ge` `lt` `le`|
|`expired`|`BOOLEAN`|`eq` `ne`|
|`timeLimitMinutes`|`INTEGER`|`eq` `ne` `gt` `ge` `lt` `le`|
|`dataUsageLimitMBytes`|`INTEGER`|`isNull` `isNotNull` `eq` `ne` `gt` `ge` `lt` `le`|
|`rxRateLimitKbps`|`INTEGER`|`isNull` `isNotNull` `eq` `ne` `gt` `ge` `lt` `le`|
|`txRateLimitKbps`|`INTEGER`|`isNull` `isNotNull` `eq` `ne` `gt` `ge` `lt` `le`|
