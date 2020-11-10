FROM ruby:2.5
MAINTAINER Paul Herbosch <paul@herbosch.be>

# RUN apt-get update && \
#     apt-get install -y net-tools redis-server

# Install gems
ENV APP_HOME /app
ENV HOME /root
RUN mkdir $APP_HOME
WORKDIR $APP_HOME
COPY Gemfile* $APP_HOME/
RUN bundle install

# Upload source
COPY . $APP_HOME

# Start server
ENV PORT 3000
EXPOSE 3000
CMD ["ruby", "app.rb"]
