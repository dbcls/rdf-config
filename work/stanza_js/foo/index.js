Stanza(function(stanza, params) {
  stanza.query({
    endpoint: "http://togogenome.org/sparql",
    template: "stanza.rq",
    parameters: params
  }).then(function(data) {
    var rows = data.results.bindings;
    stanza.render({
      template: "stanza.html",
      parameters: {
        features: rows
      },
    });
  });
});
