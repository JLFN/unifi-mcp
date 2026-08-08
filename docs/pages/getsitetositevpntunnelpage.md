# List Site-To-Site VPN Tunnels

`GET /v1/sites/{siteId}/vpn/site-to-site-tunnels`  
operationId: `getSiteToSiteVpnTunnelPage`  

Retrieve a paginated list of all site-to-site VPN tunnels on a site.


**Filterable properties (click to expand):**



|Name|Type|Allowed functions|
|-|-|-|
|`type`|`STRING`|`eq` `ne` `in` `notIn`|
|`id`|`UUID`|`eq` `ne` `in` `notIn`|
|`name`|`STRING`|`eq` `ne` `in` `notIn` `like`|
|`metadata.origin`|`STRING`|`eq` `ne` `in` `notIn`|
|`metadata.source`|`STRING`|`eq` `ne` `in` `notIn` `isNull` `isNotNull`|
