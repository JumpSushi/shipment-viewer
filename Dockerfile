FROM ruby:3.3.4

WORKDIR /code
COPY Gemfile Gemfile.lock /code/
RUN bundle install

COPY . /code

CMD ["bundle", "exec", "rackup", "--host", "0.0.0.0", "-p", "4567"]

EXPOSE 4567