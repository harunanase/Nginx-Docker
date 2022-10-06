RulePath = "/opt/nginx/conf/waf/wafconf/"
attacklog = "on"
logdir = "/opt/nginx/logs/"
UrlDeny="on"
Redirect="on"
CookieMatch="on"
postMatch="on" 
whiteModule="on" 
black_fileExt={"php","jsp"}
ipWhitelist={"127.0.0.1"}
ipBlocklist={"1.0.0.1"}
whiteDomainList={"example.com:8080"}
blackDomainList={""}
CCDeny="off"
CCrate="100/60"
html=[[<html>
<head><title>403 Forbidden</title></head>
<body>
<center><h1>403 Forbidden</h1></center>
<center>Invalid Request</center>
</body>
</html>]]
