# RDF-config specification

## endpoint.yaml

SPARQL エンドポイントを下記の記法で記述する。

```yaml
endpoint: http://example.org/sparql
```

デフォルトのエンドポイントは `endpoint:` で指定すること。同じデータを持つ複数のエンドポイントを記述しておきたい場合は下記の記法を用いる。各エンドポイントでデータの含まれるグラフ名を記述しておけば、生成される SPARQL クエリの FROM 句で使われる。

```yaml
endpoint:
  - http://example.org/sparql  # プライマリの SPARQL エンドポイント
  - graph:
    - http://example.org/graph/1
    - http://example.org/graph/2
    - http://example.org/graph/3

another_endpoint:
  - http://another.org/sparql  # 予備の SPARQL エンドポイント
  - graph:
    - http://another.org/graph/A
    - http://another.org/graph/B
```

## prefix.yaml

RDF データモデルで使われている CURIE/QName のプレフィックスは必ず下記の記法で定義しておく。

```yaml
rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
rdfs: <http://www.w3.org/2000/01/rdf-schema#>
xsd: <http://www.w3.org/2001/XMLSchema#>
dc: <http://purl.org/dc/elements/1.1/>
dct: <http://purl.org/dc/terms/>
skos: <http://www.w3.org/2004/02/skos/core#>
```

## model.yaml

RDF データモデルは基本的に YAML に準拠した下記の構造で（順序を保存し、重複した出現を許容するために）ネストした配列でもたせる。インデントがズレているとエラーになること（行頭にスペースとタブを混在させないようにすべき）、主語・述語・目的語がそれぞれがハッシュのキーとなるため末尾に `:` をつけることに注意。

```yaml
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
```yaml
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
```yaml
- Entry mydb:1:
  - a: mydb:Entry
（以下同様）
```

主語が空白ノードの場合：
```yaml
- []:
  - a: mydb:Entry
（以下同様）
```

主語については、GraphQLでの型名（変数名）、RDFでの型（URI)、サンプル例（URI)の３つを与える必要があり、RDFでの型とサンプル例は複数になることもあり得る。複数のサンプル例を載せたい場合はスペース区切りで列挙する。

```yaml
- Entry mydb:1 mydb:2:
  - a: mydb:Entry
（以下同様）
```

### 述語

主語にぶら下がる述語を URI (`<http://...>`) か CURIE/QName (`prefix:local_part`) で配列として列挙する。

述語に対応する目的語に許容される出現回数の制約を、述語の末尾に下記の記号をつけることで明示できる。

* なし: 判定しない（対応する値が「1つある」つまり `{1}` を仮定していると解釈する）
* `?`: 0個もしくは1個（対応する値が「無い」か「１つに限られる」場合 →  OPTIONAL 句になる）
* `*`: 0個もしくは複数個（対応する値が「無い」か「複数の可能性がある」場合 →  OPTIONAL句になる）
* `+`: 1個以上（対応する値は「有る」はずで、「複数の可能性がある」場合）
* `{n}`: n個（対応する値が「n個」に限られる場合）
* `{n,m}`: n個からm個（対応する値が「n個」以上「m個」以下に限られる場合）

この指定は SPARQL クエリを OPTIONAL 句にするかどうかと、ShEx による RDF のバリデーションに用いられる。

```yaml
- Subject my:subject:
  - a: my:Class
  - my:predicate1?:
    - string_label: "This is my value"
  - my:predicate2*:
    - integer_value: 123
  - my:predicate3+:
    - date_value: 2020-05-21
  - my:predicate4{2}:
    - integer_value: 123, 456
  - my:predicate5{3,5}:
    - integer_value: 123, 456, 789
```

ただし、RDF データは開世界仮説 (Open world assumption) なので、述語に対応する値が必ず１つである（複数存在しない）ことを保証できないため、「`predicate`と`predicate+`」および「`predicate?`と`predicate*`」の区別は SPARQL のレベルでは生じないことに注意。

### 目的語

述語にぶら下がる目的語は、目的語の名前およびその例を記述する。目的語の名前は、SPARQL クエリの変数名として使われるため、model.yaml ファイル内で一意なものを snake_case で設定すること。

目的語の例は省略してもよいが、スキーマ図を分かりやすくするためにも必ずつけることを推奨する。その値は YAML パーザが型を推定するので、文字列（必ずしもクオートしなくてもYAMLとしては問題ない）、数値、日付などはそのまま記述できる。URI は YAML では文字列として扱われてしまうため、RDF-config では `<>` で囲まれた文字列および CURIE/QName（プレフィックスが prefix.yaml で定義されているもの）は特別に URI として解釈する。

```yaml
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

目的語が他の RDF モデルを参照する場合は、目的語に参照先の主語名を記述する。（TODO: FALDOなど共通に使えるデータモデルを外部参照できるように拡張する）

```yaml
- Subject my:subject:
  - my:refer:
    - other_subject: OtherSubject  # 同じ model.yaml 内で主語として使われている主語名
- OtherSubject my:other_subject:
  - a: my:OtherClass
```

目的語の例が複数行にわたる場合は YAML の記法で `|` を用いることでインデントした部分を複数行リテラルとして扱われる。ただし、あまり長いとスキーマ図で表示できない、もしくは表示が崩れる可能性があることに注意。

```yaml
- Subject my:subject:
  - my:predicate:
    - value: |
        long long line of
         example explanation
        in detail
```

言語タグ（`"hoge"@en`, `"ほげ"@ja` など）は下記のように指定すれば良さそう。
（`''` で囲まないと YAML としてエラーになる）

```yaml
- Subject my:subject:
  - my:predicate:
    - name: '"hoge"@en'
```

リテラルの`^^`による型指定（`"123"^^xsd:string` など）は下記のように指定すれば良さそう。
（`''` で囲まないと YAML としてエラーになる）

```yaml
- Subject my:subject:
  - my:predicate:
    - myvalue: '"123"^^xsd:integer'
```

## schema.yaml

モデルが複雑な場合に主要な部分だけのスキーマ図を描きたいなど、モデルのサブセットからスキーマ図生成する際に設定するファイルで、下記の YAML 形式で記述する。なお、このファイルがなくても全体のスキーマ図は生成可能。

```yaml
スキーマ名1:
  description: スキーマ図に載せる主語名や目的語名のリスト
  variables: [ 主語名1, 主語名2, 目的語名1, 目的語名2, 目的語名3 ]

スキーマ名2:
  description: 目的語が指定されていれば、その主語からはその目的語だけをぶら下げた図を作る
  variables: [ 目的語名1, 目的語名2, 目的語名3 ]

スキーマ名3:
  description: 主語だけが指定されていれば、その主語からぶら下がる全ての目的語を表示した図を作る
  variables: [ 主語名1, 主語名2 ]

スキーマ名4:
  description: スキーマ図に載せるタイトルだけを指定
```

## sparql.yaml

複数の SPARQL クエリを設定できるファイルで、下記の YAML 形式で記述する。

RDF-config では、対象となる目的語の名前から、必要となる property paths を同定し SPARQL クエリを自動生成するため、結果として得たい変数名を variables に列挙するだけでよい。ID や名前など、値の一部を引数として与えるクエリを作成する場合は、parameters に値をセットする変数名とそのデフォルト値を指定する。

```yaml
クエリ名:
  description: 何をする SPARQL クエリなのか説明
  variables: [ foo, bar, ... ]  # SPARQL で SELECT の対象とする目的語の名前（変数名）を列挙

引数を取る別のクエリ名:
  description: 何をする SPARQL クエリなのか説明
  variables: [ foo, bar, ... ]  # SPARQL で SELECT の対象とする目的語の名前（変数名）を列挙
  parameters:
    目的語の名前: デフォルト値

オプションを取る別のクエリ名:
  description: 何をする SPARQL クエリなのか説明
  variables: [ foo, bar, ... ]  # SPARQL で SELECT の対象とする目的語の名前（変数名）を列挙
  options:
    distinct: true   # SELECT DISTINCT ...
    limit: 500       # LIMIT 句を消すには false を指定
    offset: 200
    order_by:        # ORDER BY ?var1 DESC(?var2) ?var3
    - var1: asc      # 昇順ソート
    - var2: desc     # 降順ソート
    - var3           # asc は省略可能
```

注意点として、変数名を持つ主語が、目的語名として複数の主語にぶら下がる形で再利用されている場合、その変数が全ての出現箇所で同じ値をもつことを前提とした SPARQL が生成されるので、必要に応じて意図した SPARQL になるよう手作業で変数名を修正する必要がある。

## convert.yaml

CSVファイル、XMLファイル、JSONファイルからRDFやJSON-LDを生成するルール（手順）を定義するファイルで、下記のYAML形式で記述する。

```yaml
主語名1:
  - 処理1-1
  - 処理1-2
  - 処理1-3
  # ... 以降、主語名1に対する処理が続く
  - variables:
      - 目的語名1-1: 処理1-1
      - 目的語名1-2:
          - 処理1-2-1
          - 処理1-2-2
          - 処理1-2-3
      - 目的語名1-3: 処理1-3
      # ... 以降、主語名1に結びつく目的語に対する処理が続く

主語名2:
  - 処理2-1
  - 処理2-2
  - 処理2-3
  # ... 以降、主語名2に対する処理が続く
  - variables:
      - 目的語名2-1: 処理2-1
      - 目的語名2-2:
          - 処理2-2-1
          - 処理2-2-2
          - 処理2-2-3
      - 目的語名2-3: 処理2-3
      # ... 以降、主語名2に結びつく目的語に対する処理が続く
# ... 以降、model.yaml内の主語に対する処理が続く
```

主語名または目的語名の部分は、`model.yaml`での主語名、目的語名を記述する。  
処理の部分は、キーとなっている主語名、目的語名に対応する値（RDFでのリソースURI、プロパティ値）を生成するためのルールを記述する。  
処理の実体はRubyで記述されたメソッドで、ある値に対して処理（Rubyのメソッド）を実行した値を返す機能を持つ。  
値の生成ルールは1個以上の処理からなり、処理が複数ある場合は値の生成ルールを処理の配列で指定する。
この場合、処理は配列の順番で実行され、各処理で処理の対象となる値は、前の処理で生成された値となる。
そして、最後の処理を実行して生成された値が、そのキーに対応する値となる。  

例えば、上の`convert.yaml`で主語名1の目的語名1-2では、3つの処理が記述されているが、目的語1-2の値を生成する処理として、
最初に処理1-2-1が実行され、処理1-2-1で生成された値に対して処理1-2-2を実行、
処理1-2-2で生成された値に対して処理1-2-3が実行され、処理1-2-3で生成された値が目的語1-2のプロパティ値となる。

処理はrdf-configでは以下の処理を提供している。

| 処理名          | 処理内容                                                                                                                                                       |
|--------------|------------------------------------------------------------------------------------------------------------------------------------------------------------|
| append       | `append(str)`<br/>値の末尾にstr追加する。                                                                                                                            |
| capitalize   | `capitalize`<br/>値（文字列）の先頭を大文字にする。                                                                                                                         |
| change_value | `change_value(rule1, rule2, ...)`<br/>引数に配列渡し、その配列の1番目の要素を2番目の要素に変更する。<br/>例えば `chage_value(['E', 'en'], ['J', 'ja'])`とすると、'E' は 'en' に、'J' は 'ja' に変更される。 |
| csv          | `csv(col_name)`<br/>CSVのcol_nameカラムの値を取得する。                                                                                                                |
| datatype     | `datatype(type)`<br/>`type`には`xsd:date`等のRDFでのデータ型を指定し、値がそのデータ型となるようにする。                                                                                   |
| delete       | `delete(pattern)`<br/>`pattern`にマッチする部分を削除する。`pattern`には文字列または正規表現を指定する。                                                                                   |
| downcase     | `downcase`<br/>文字列を全て小文字に変換する。                                                                                                                             |
| join         | `join(str1, str2, ..., strN, sep)`<br/>`str1`から`strN`を文字列`sep`を間に挟んで連結する。                                                                                  |
| json         | `json(key)`<br/>JSONから値を取得する。JSONが階層構造になっている場合、`key1.key2.key3`のように、たどるキー名をドットでつなげた値を`key`に指定する。                                                           |
| lang         | `lang(lang_tag)`<br/>RDFの言語タグを設定する。                                                                                                                        |
| prepend      | `prepend(str)`<br/>値の先頭に引数で指定された文字列を追加する。                                                                                                                  |
| replace      | `replace(pattern, replace)`<br/>`pattern`にマッチする部分を`replace`で置き換える。<br/>`pattern`には置き換える文字列か正規表現を指定し、文字列を指定した場合は全く同じ文字列にだけマッチする。                            |
| source       | `source(filepath)`<br/>変換対象とするファイルを指定する。                                                                                                                   |
| split        | `split(sep)`<br/>値を`sep`で分割する。                                                                                                                             |
| to_bool      | `to_bool`<br/>値を真偽値に変換する。                                                                                                                                  |
| to_int       | `to_int`<br/>値を整数に変換する。                                                                                                                                    |
| tsv          | `tsv(col_name)`<br/>TSVのcol_nameカラムの値を取得する。                                                                                                                |
| upcase       | `upcase`<br/>文字列を全て大文字に変換する。                                                                                                                               |
| xml          | xml(xpath)<br/>XMLの`xpath`にマッチする最初の要素の値を取得する。                                                                                                              |

上記の処理以外の処理を実行したい場合は、独自の処理を追加できる。  
処理の実体はRubyのメソッドであり、処理を記述したRubyファイルを`lib/rdf-config/convert/macros`配下に保存する。  
その際、ファイル名は`処理名.rb`とする。

### 主語の生成ルール
主語名から`-variables:`までの間に主語のリソースURIを生成するルールを記述する。  
主語名の部分には`model.yaml`での主語名を記述する。  
YAMLの主語名（キー）に対応する値には、その主語名に対応するリソースURIを生成するルールを記述する。  
以下は、主語に対する`convert.yaml`の記述例である。

```yaml
MySubject:
  - source("/path/to/csv_file.csv")
  - csv("id_column")
  - prepend("http://example.org/my_subject/")
```

この場合、以下のように`MySubject`の値が生成される。
1. 変換元のCSVファイルを`/path/to/csv_file.csv`に設定する。
2. `/path/to/csv_file.csv`ファイルの`id_column`カラムの値を取得する。
3. 上記で取得した値の先頭に http://example.org/my_subject/ を追加する。

この結果、`id_column`の値が 1 の場合、`MySubject` の値は、上記の処理2. で値 1 が取得され、  
処理3. で、処理2. で取得された値（= 1）の先頭に http://example.org/my_subject/ を追加するので、  
その結果
http://example.org/my_subject/1 
となる。

### 目的語の値の生成ルール
主語の生成ルールに続けて、`-variables:`以降に、主語に結びつく目的語のRDFにおける値（プロパティ値）を生成するルールを記述する。
`-variables:`以下の配列要素の各キーにはmodel.yamlでの目的語名を記述する。

以下は、目的語に対する`convert.yaml`の記述例である。
```yaml
MySubject:
  - source("/path/to/csv_file.csv")
  - csv("id_column")
  - prepend("http://example.org/my_subject/")
  - variables:
    - my_label:
      - csv("label")
      - lang("ja")
    - my_date:
      - csv("date")
      - datatype("xsd:date")
```

上記の`convert.yaml`の目的語（my_label, my_data）の生成ルールは以下のように解釈することができる。
* my_labelのプロパティ値 = CSVファイルのlabelカラムの値にRDFの言語タグ"ja"が付加されたRDFリテラル値
* my_dateのプロパティ値 = CSVファイルのdateカラムにデータ型"xsd:date"が付加されたRDFリテラル値

#### RDFの言語タグ、データ型の付与
上記の例では、`convert.yaml`にRDFの言語タグやデータ型を付与する処理を記述しているが、
`model.yaml`のオブジェクトの例に言語タグやデータ型が付与されている場合は、それらを参照して
プロパティ値の言語タグやデータ型を判断するため、`convert.yaml`で言語タグやデータ型の付与の処理を
記述する必要はない。

例えば `model.yaml` で以下のように、目的語の例に言語タグやデータ型が付与されているとする。  
`model.yaml`（目的語の例に言語タグやデータ型が付与されている）
```yaml
MySubject <http://example.org/my_subject/1>
  - my:label:
    - my_label "マイラベル"@ja
  - my:date:
    - my_date "2023-04-01"^^xsd:date
```

この場合、以下の`convert.yaml`のように言語タグやデータ型の付与処理を記述しなくても、
生成されるRDFでは、`model.yaml`の目的語の例に従って、言語タグやデータ型が付与される。  
`convert.yaml`（言語タグやデータ型の付与処理を省略したパターン）
```yaml
MySubject:
  - source("/path/to/csv_file.csv")
  - csv("id_column")
  - prepend("http://example.org/my_subject/")
  - variables:
    - my_label: csv("label")
    - my_date: csv("date")
```

#### RDFでのURI、リテラル
`convert.yaml`の設定内容に従って生成されたRDFプロパティ値がURIになるか、リテラルになるかどうかは、
`model.yaml`でのオブジェクトの例によって決まる。

例えば、以下の`model.yaml`と`convert.yaml`を考える。  
`model.yaml`
```yaml
MySubject <http://example.org/my_subject/1>
  - rdfs:seeAlso:
    - uniprot: <http://identifiers.org/uniprot/Q9NQ94>
```

`convert.yaml`
```yaml
MySubject:
  - source("/path/to/csv_file.csv")
  - csv("id_column")
  - prepend("http://example.org/my_subject/")
  - variables:
    - uniprot:
      - csv("uniprot_id")
      - prepend("http://identifiers.org/uniprot/")
```

`model.yaml`では目的語`uniprot`の値の例がRDFのURIの形式になっているため、
`convert.yaml`に従って生成されたRDFの`uniprot`のプロパティ値もRDFのURIになる。

### 変数の使用
`convert.yaml`では、変数に値をセットし、それを別の場所で参照することができる。  
変数を値にセットするには、キーに変数名を記述し、そのキーに対応する値の部分に、変数に値をセットするルールを記述する。

```YAML
主語名:
  - 処理
  - $var1: 処理
  # ...
  - variables:
    - $var2:
      - 処理
      - 処理
    - 目的語名:
      - 処理
      - 処理
    # ...
```

上記のようにキーが$で始まっている場合は、`convert.yaml`内で参照できる変数となる。  
$で始まる変数に対応する処理を行った結果が変数の値としてセットされ、
convert.yaml内の別の場所から変数の値を参照（使用）することができる。  
例えば、上記のYAMLでは`$var2`にセットされた値を目的語名の処理の部分で使うことができる。  
具体的に、変数の値を利用するには以下の2つの方法がある。
1. 処理の部分に変数名を埋め込んだ文字列を指定する。<br/>⇒ 例えば、処理の部分に "string$varname" と指定され、`$varname`の値が my_valとすると`$varname`の値が展開された "stringmy_val" が処理の結果となる。
2. 処理の引数に変数名を与える。<br/>⇒ 変数名の値を引数として、処理が実行される。

以下は、変数を利用する例である。

CSVファイル（`person.csv`）

| person_id | first_name | last_name |lang|
|-----------|------------|-----------|----|
|1| 一郎         | 鈴木        |ja|


`model.yaml`
```yaml
- Person <http://example.org/ontology/person/1>:
  - a: foaf:Person
  - dct:identifier:
      - person_id: 1
  - foaf:name:
      - name: Taro YAMADA
```

`convert.yaml`
```yaml
Person:
  - source("/path/to/person.csv")
  - $id: csv("person_id")
  - "http://example.org/ontology/person/$id"
  - variables:
    - person_id: $id
    - name:
      - $first_name: csv("first_name")
      - $last_name: csv("last_name")
      - $lang: csv("lang")
      - "$last_name $first_name"
      - lang($lang)
```

以下のように、リソースURIとプロパティ値が生成される。
1. 主語`Person`のリソースURIの生成
   1. 入力のCSVファイルを/path/to/person.csvとする。
   2. CSVファイルの`person_id`カラムの値を取得し、それを変数`$id`にセットする。
   3. `Person`のリソース値を "http://example.org/ontology/person/$id" とする。<br />⇒ `$id`の値が1にセットされているため、`$id`が1に展開され、 "http://example.org/ontology/person/1" となる。
2. 目的語`person_id`のプロパティ値の生成<br />⇒ `$id`が1なので`person_id`のプロパティ値は1となる。
3. 目的語`name`のプロパティ値の生成
   1. CSVファイルのfirst_nameカラムの値を変数`$first_name`にセットする。
   2. CSVファイルのlast_nameカラムの値を変数`$last_name`にセットする。
   3. CSVファイルのlangカラムの値を変数`$lang`にセットする。
   4. `name`のプロパティ値を "$last_name　$first_name" とする。<br />⇒ `$last_name`と`$first_name`の値が展開され "鈴木 一郎" となる。
   5. `$lang`の値が "ja" なので、`name`のプロパティ値は "鈴木 一郎"@ja となる。

上記の結果、以下のようなRDFが生成される。
```
<http://example.org/ontology/person/1> a foaf:Person;
  dct:identifier 1;
  foaf:name "山田 太郎"@ja .
```

## stanza.yaml

TogoStanza を生成する際に必要な metadata.json ファイルのための情報を記述する。

```yaml
スタンザ名:
  output_dir: /path/to/output/dir     # 出力先ディレクトリ名（TODO: ここに書くのではなくコマンドラインで自由に変更できるようにすべきか）
  label: "スタンザの名前"
  definition: "スタンザの説明"
  sparql: pair_stanza                 # sparql.yaml で定義した対応する SPARQL クエリの名前
  parameters:
    変数名:
      example: デフォルト値
      description: 説明
      required: true                  # 省略可能パラメータかどうか (true/false)
```

