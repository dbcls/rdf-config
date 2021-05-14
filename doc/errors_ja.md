# エラーメッセージ一覧
## Duplicate subject name (主語名) in model.yaml file.
model.yamlで同一の主語名が複数回設定されている。  
解決策）主語名をmodel.yaml内でユニークにする。

## Duplicate variable name (目的語名) in model.yaml file.
model.yamlで同一の目的語名が複数回設定されている。  
解決策）目的語名をmodel.yaml内でユニークにする。

## Invalid object name (目的語名) in model.yaml file. Only lowercase letters, numbers and underscores can be used in object name.
目的語がRDF-configの仕様を満たしていない。  
解決策）目的語名はsnake_caseで、目的語に使用する文字は英小文字、数字、アンダースコアのみにする。

## Invalid subject name (主語名) in model.yaml file. Subject name must start with a capital letter and only alphanumeric characters can be used in subject name.
主語名がRDF-configの仕様を満たしていない。  
解決策）主語名はCamelCaseで、主語名に使用する文字は英字のみにする。

## It seems that the predicate and object settings in subject (主語名) are incorrect in the model.yaml file.
主語名配下の述語、目的語の設定がRDF-configの仕様を見たしいない可能性がある。  
解決策）述語、目的語の設定がRDF-configの仕様に合っているか確認する。具体的には、以下の設定を確認する。
- 述語、目的語がYAMLの配列で設定されているかどうか。
- 述語や目的語のインデントがずれていないかどうか。例えば、述語と目的語が同じインデントになっていないかどうか。

## Predicate (述語URI) has no RDF object setting.
述語に目的語が設定されていない。  
解決策）以下の設定を確認する。
- 述語と目的語がYAMLで同じインデントになっていないかどうか。述語と目的語の設定で、述語と目的語が同じインデントになっている場合、RDF-configは、目的語の部分を述語と解釈し、目的語が設定されていないと判断する。

## Predicate (述語URI) is not valid URI.
述語がURIではない。  
解決策）述語に正しいURIの形式（prefix:local_partや \<http://...\> のような形式）を設定する。

## Prefix (名前空間プレフィックス) used in predicate (述語URI) but not defined in prefix.yaml file.
述語のURIで使用されている名前空間プレフィックスがprefix.yamlに設定されていない。  
解決策）prefix.yamlに名前空間プレフィックスとそれに対応するURIを設定する。

## Prefix (名前空間プレフィクス) used in rdf:type (rdf:typeのURI) but not defined in prefix.yaml file.
rdf:typeのURIで使用されている名前空間プレフィックスがprefix.yamlに設定されていない。  
解決策）prefix.yamlに名前空間プレフィックスとそれに対応するURIを設定する。

## Prefix (名前空間プレフィックス) used in subject (主語名), value (主語の例) but not defined in prefix.yaml file.
主語のサンプル値に使用されている名前空間プレフィックスがprefix.yamlに設定されていない。  
解決策）prefix.yamlに名前空間プレフィックスとそれに対応するURIを設定する。


## RDF object data (predicate is '述語URI') in model.yaml is not an array. Please specify the RDF object data as an array.
述語配下の目的語の設定が配列になっていない。  
解決策）目的語は配列で設定する。（RDF-configの仕様として、目的語は配列で指定することになっている）

## rdf:type (rdf:typeのURI) is not valid URI.
rdf:typeの値がURIではない。  
解決策）rdf:typeの値に正しいURIの形式（prefix:local_partや \<http://...\> のような形式）を設定する。

## Subject (主語名), value (主語のサンプル値) is not valid URI.
主語のサンプル値がURIではない。  
解決策）主語のサンプル値に正しいURIの形式（prefix:local_partや \<http://...\> のような形式）を設定する。


# ワーニングメッセージ一覧
## Multiple object names (目的語名) are set in the same property path (プロパティ・パス)
model.yamlを元に生成されるSPARQLで、同一のプロパティ・パスとなる目的語が複数ある。  
この場合、その目的語名が全ての出現箇所で同じ値をもつことを前提とした SPARQL が生成されるので、必要に応じて意図した SPARQL になるよう手作業でSPARQL変数名を修正する必要がある。

## Subject (主語名) has no rdf:type.
主語にrdf:typeが設定されていない。主語にはrdf:typeを設定することを推奨する。

## Variable name (変数名) is set in sparql.yaml file, but not in model.yaml file.
sparql.yamlのvariablesに設定されている主語名、目的語名がmodel.yamlで設定されていない。SPAQRL生成の際、model.yamlで設定されていない変数は無視される。
