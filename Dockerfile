FROM ruby:3.0-slim-buster
MAINTAINER Paul Herbosch <paul@herbosch.be>

RUN apt-get update && \
    apt-get install -y libcurl4 libcurl3-gnutls libcurl4-gnutls-dev curl build-essential default-libmysqlclient-dev

# Install gems
ENV APP_HOME /app
ENV HOME /root
RUN mkdir $APP_HOME
WORKDIR $APP_HOME
COPY Gemfile* $APP_HOME/
RUN bundle install

# Start server
ENV PORT 3000
EXPOSE 3000
CMD ["ruby", "app.rb"]
