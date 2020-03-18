# RDF-config specification

## endpoint.yaml

SPARQL エンドポイントを下記の記法で記述する。

```
endpoint: http://example.org/sparql
```

同じデータを持つ複数のエンドポイントを記述しておきたい場合は下記の記法を用いる。

```
endpoint:
  - http://example.org/sparql  # プライマリの SPARQL エンドポイント
  - http://another.org/sparql  # 予備の SPARQL エンドポイント
```

## prefix.yaml

RDF データモデルで使われている CURIE/QName のプレフィックスは必ず下記の記法で定義しておく。

```
rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
rdfs: <http://www.w3.org/2000/01/rdf-schema#>
xsd: <http://www.w3.org/2001/XMLSchema#>
dc: <http://purl.org/dc/elements/1.1/>
dct: <http://purl.org/dc/terms/>
skos: <http://www.w3.org/2004/02/skos/core#>
```

## model.yaml

RDF データモデルは基本的に YAML に準拠した下記の構造で（順序を保存し、重複した出現を許容するために）ネストした配列でもたせる。インデントがズレているとエラーになること（行頭にスペースとタブを混在させないようにすべき）、主語・述語・目的語がそれぞれがハッシュのキーとなるため末尾に `:` をつけることに注意。

```
- 主語名 主語の例1 主語の例2:
  - 述語:
    - 目的語名1: 目的語の例1
  - 述語:
    - 目的語名2: 目的語の例2
    - 目的語名3: 目的語の例3
    - 目的語名4: 目的語の例4
  - 述語:
    - []:  # 空白ノード
      - 述語:
        - 目的語名: 目的語の例
    - []:
      - 述語:
        - []:  # ネストした空白ノード
          - 述語:
            - 目的語名: 目的語の例
```

主語の例、述語、目的語の例は URI (`<http://...>`) か CURIE/QName (`prefix:local_part`) で記述する。目的語の例はリテラルでも良く、どうしても必要なら例を複数指定してもよい。なお、空白ノードは `[]` で表す。

主語名、目的語名は、SPARQL 検索や結果を表示する際に利用する変数名となるので意味がわかりやすい名前をつける。主語名は CamelCase の名前、目的語名は snake_case の名前を用いることとする。

誰にとっても、name という変数に生年月日が入っていることを想定したり、obj1 という変数に入っている 42 という値が何を意味するのか考えることは苦痛で不毛なので、RDF-config において最も重要なポイントは、値の意味を表す適切な変数名の設定にあるといっても過言ではない。また、同じカラム名が複数回出現するような表データは、その意味の違いを考えながら名前を付け替えないと扱いにくいが、そのアナロジーからも各「変数名」を model.yaml ファイル内で「ユニーク」かつ「分かりやすく」しておくことこそがポイントである。

### 主語

主語名につづいて、空白区切りで主語の URI の例を記述する（省略可）。主語には `rdf:type` (`a`) を必ず指定すること。さらに `rdfs:label` または `dct:identifier` を追記することを強く推奨する。

主語が URI の場合：
```
- Entry <http://example.org/mydb/entry/1>:
  - a: mydb:Entry  # 型が一つの場合
  - a:             # 型が複数の場合
    - mydb:Entry
    - hoge:Fuga
  - rdf:type:      # rdf:type の短縮形 a を使わないで書く場合 prefix.yaml に rdf: を定義
    - mydb:Entry
    - hoge:Fuga
  - rdfs:label:
    - label: "1"
  - dct:identifier:
    - id: 1
```

主語が CURIE/QName の場合：
```
- Entry mydb:1:
  - a: mydb:Entry
（以下同様）
```

主語が空白ノードの場合：
```
- []:
  - a: mydb:Entry
（以下同様）
```

主語については、GraphQLでの型名（変数名）、RDFでの型（URI)、サンプル例（URI)の３つを与える必要があり、RDFでの型とサンプル例は複数になることもあり得る。複数のサンプル例を載せたい場合はスペース区切りで列挙する。

```
- Entry mydb:1 mydb:2:
  - a: mydb:Entry
（以下同様）
```

### 述語

主語にぶら下がる述語を URI (`<http://...>`) か CURIE/QName (`prefix:local_part`) で配列として列挙する。

### 目的語

述語にぶら下がる目的語は、目的語の名前およびその例を記述する。目的語の名前は、SPARQL クエリの変数名として使われるため、model.yaml ファイル内で一意なものを snake_case で設定すること。

目的語の例は省略してもよいが、スキーマ図を分かりやすくするためにも必ずつけることを推奨する。その値は YAML パーザが型を推定するので、文字列（必ずしもクオートしなくてもYAMLとしては問題ない）、数値、日付などはそのまま記述できる。URI は YAML では文字列として扱われてしまうため、RDF-config では `<>` で囲まれた文字列および CURIE/QName（プレフィックスが prefix.yaml で定義されているもの）は特別に URI として解釈する。

```
- Subject my:subject:
  - a: my:Class
  - my:predicate1:
    - string_label: "This is my value"
  - my:predicate2:
    - integer_value: 123
  - my:predicate3:
    - float_value: 123.45
  - my:predicate4:
    - curie: my:sample123
  - rdfs:seeAlso:
    - xref: <http://example.org/sample/uri>
```

述語が取りうる目的語の有無（SPARQLのOPTIONALの有無）やその数（単数複数）を、目的語名 `var` の後に下記の記号をつけることで明示できる。

* `var`: 対応する値は「有る」はずで、「1つに限られる」場合
* `var+`: 対応する値は「有る」はずで、「複数の可能性がある」場合
* `var?`: 対応する値が「無い」か「１つに限られる」場合 →  OPTIONAL 句になる
* `var*`: 対応する値が「無い」か「複数の可能性がある」場合 →  OPTIONAL句になる

ただし、RDF/SPARQL では、変数に対応する値が必ず１つである（複数存在しない）ことを保証できないため、「`var`と`var+`」および「`var?`と`var*`」の区別はSPARQLのレベルでは生じないことに注意。

```
- Subject my:subject:
  - my:single:
    - var: "hoge"
  - my:single_optional:
    - var?: "hoge"
  - my:multiple:
    - var+: "hoge", "fuga"
  - my:multiple_optional:
    - var*: "hoge", "fuga"
```

目的語が他の RDF モデルを参照する場合は、目的語に参照先の主語名を記述する。（TODO: FALDOなど共通に使えるデータモデルを外部参照できるように拡張する）

```
- Subject my:subject:
  - my:refer:
    - other_subject: OtherSubject  # 同じ model.yaml 内で主語として使われている主語名
- OtherSubject my:other_subject:
  - a: my:OtherClass
```

目的語の例が複数行にわたる場合は YAML の記法で `|` を用いることでインデントした部分を複数行リテラルとして扱われる。ただし、あまり長いとスキーマ図で表示できない、もしくは表示が崩れる可能性があることに注意。

```
- Subject my:subject:
  - my:predicate:
    - value: |
        long long line of
         example explanation
        in detail
```

言語タグ（`"hoge"@en`, `"ほげ"@ja` など）は下記のように指定すれば良さそう。
（`''` で囲まないと YAML としてエラーになる）

```
- Subject my:subject:
  - my:predicate:
    - name: '"hoge"@en'
```

リテラルの`^^`による型指定（`"123"^^xsd:string` など）は下記のように指定すれば良さそう。
（`''` で囲まないと YAML としてエラーになる）

```
- Subject my:subject:
  - my:predicate:
    - myvalue: '"123"^^xsd:integer'
```

## sparql.yaml

複数の SPARQL クエリを設定できるファイルで、下記の YAML 形式で記述する。

RDF-config では、対象となる目的語の名前から、必要となる property paths を同定し SPARQL クエリを自動生成するため、結果として得たい変数名を variables に列挙するだけでよい。ID や名前など、値の一部を引数として与えるクエリを作成する場合は、parameters に値をセットする変数名とそのデフォルト値を指定する。

```
クエリ名:
  description: 何をする SPARQL クエリなのか説明
  variables: [ foo, bar, ... ]  # SPARQL で SELECT の対象とする目的語の名前（変数名）を列挙

別のクエリ名:
  description: 何をする SPARQL クエリなのか説明
  variables: [ foo, bar, ... ]  # SPARQL で SELECT の対象とする目的語の名前（変数名）を列挙
  parameters:
    目的語の名前: デフォルト値
```

## stanza.yaml

TogoStanza を生成する際に必要な metadata.json ファイルのための情報を記述する。

```
スタンザのID:
  output_dir: /path/to/output/dir     # 出力先ディレクトリ名
  label: "スタンザの名前"
  definition: "スタンザの説明"
  sparql: pair_stanza                 # sparql.yaml で定義した対応する SPARQL クエリの名前
  parameters:
    変数名:
      example: デフォルト値
      description: 説明
      required: true                  # 省略可能パラメータかどうか (true/false)
```


