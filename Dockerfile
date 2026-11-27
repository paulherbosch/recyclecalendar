# The base image is also written into a label, so image scanners can tell what the image was built from.
# The second ARG is needed: without it the label is empty.
ARG BASE=ruby:3.3-slim-bookworm
FROM ${BASE}
ARG BASE
LABEL org.opencontainers.image.base.name=${BASE}
MAINTAINER Paul Herbosch <paul@herbosch.be>

# The gems openssl, mysql2, curb and cap2 (pulled in by net-ping) compile against these
RUN apt-get update \
	&& apt-get install -y --no-install-recommends \
		ca-certificates \
		curl \
		build-essential \
		libssl-dev \
		default-libmysqlclient-dev \
		libcurl4-openssl-dev \
		libcap-dev \
	&& rm -rf /var/lib/apt/lists/*

# Install gems
ENV APP_HOME /app
ENV HOME /root
RUN mkdir $APP_HOME
WORKDIR $APP_HOME
COPY Gemfile* $APP_HOME/
RUN bundle install

# Start server
# Production: in development mode Sinatra (4.1 and newer) answers only to localhost, so requests to any other
# hostname get 403 Forbidden
ENV APP_ENV production
ENV PORT 3000
EXPOSE 3000
CMD ["ruby", "app.rb"]
