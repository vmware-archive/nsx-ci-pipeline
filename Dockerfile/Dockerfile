FROM ubuntu:17.04

RUN apt-get update && apt-get install -y vim curl wget default-jdk maven gradle golang git jq python ruby-dev python-pip python-dev libffi-dev libssl-dev libxml2-dev libxslt1-dev zlib1g-dev
RUN pip install --upgrade pip && pip install six pynsxv pyquery xmltodict ipcalc click Jinja2 shyaml dicttoxml pprint PyYAML requests
RUN wget -O cf-cli.deb "https://cli.run.pivotal.io/stable?release=debian64&source=github-rel" && dpkg -i cf-cli.deb
RUN cf --version && java -version && mvn -v && gradle -v && go version
RUN ls -al $HOME && mkdir $HOME/go
ENV GOPATH $HOME/go/
ENV GOBIN $GOPATH/bin
ENV PATH $PATH:$GOBIN
RUN go get github.com/pivotal-cf/om
RUN go get github.com/pivotal-cf/pivnet-cli
RUN go get github.com/vmware/govmomi/govc
RUN gem install cf-uaac
