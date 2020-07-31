FROM ruby:2.7.1
COPY . /rdf-config
ENV PATH=/rdf-config/bin:${PATH}
ENV RUBYLIB=/rdf-config/lib
CMD ["rdf-config"]
