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

CSVファイル、TSVファイルからRDFやJSON-LDを生成するルール（手順）を定義するファイルで、下記のYAML形式で記述する。

```yaml
主語名1:
  # 変換元ファイルパスの設定や変数に値を設定する処理
  - 処理1-1
  - 処理1-2
  - 処理1-3
  - subject: # 以下に主語名1の値を生成するルールを記述する
    - 主語名1の生成処理1
    - 主語名1の生成処理2
    # ... 以降、主語名1の生成処理が続く
  - objects: # 以下に主語名1に結びつく目的語の値を生成するルールを記述する
    - 目的語名1-1: 目的語名1-1の生成処理
    - 目的語名1-2: # 生成処理が複数ある場合は、以下のように配列で記述する
      - 目的語名1-2の生成処理1
      - 目的語名1-2の生成処理2
      - 目的語名1-2の生成処理3
    - 目的語名1-3: 目的語名1-3の生成処理
    # ... 以降、主語名1に結びつく目的語の生成ルールが続く

主語名2:
  # 変換元ファイルパスの設定や変数に値を設定する処理
  - 処理2-1
  - 処理2-2
  - 処理2-3
  - subject:
    # 主語名2の生成ルールを記述する
    ...
  - objects:
    - 目的語名2-1: 目的語名2-1の生成処理
    - 目的語名2-2:
      - 目的語名2-2の生成処理1
      - 目的語名2-2の生成処理2
      - 目的語名2-2の生成処理3
    - 目的語名2-3: 目的語名2-3の生成処理
    # ... 以降、主語名2に結びつく目的語の生成ルールが続く

# ... 以降、model.yaml内の主語に対する生成ルールが続く
```

主語名または目的語名の部分は、`model.yaml`での主語名、目的語名を記述する。  
生成処理の部分は、キーとなっている主語名、目的語名に対応する値（RDFでのリソースURI、プロパティ値）を生成するためのルールを記述する。  
生成処理の実体はRubyで記述されたメソッドで、入力値に対して生成処理（Rubyのメソッド）を実行した値を返す機能を持つ。  
主語のURIや目的語の値の生成ルールは1個以上の生成処理からなり、生成処理が複数ある場合は、値の生成ルールを生成処理の配列で指定する。  
（上記`convert.yaml'の例の、主語名1のsubject, 目的語名1-2, 目的語名2-2 の部分）  
この場合、生成処理は配列要素の順番で実行され、各生成処理で処理の対象となる値（入力値）は、前の生成処理で生成された値となる。  
そして、最後の生成処理を実行して生成された値が、そのキーに対応する値となる。  

例えば、上の`convert.yaml`で主語名1の目的語名1-2では、3つの生成処理が記述されているが、これは、目的語1-2の値を以下のように生成する設定となっている。
1. 目的語名1-2の生成処理1が実行される。<br/>通常、最初の生成処理は`csv(column_name)`や`tsv(column_name)`でカラムの値を取得する処理となる。
2. 上記 1.の生成処理で生成された値を入力値として目的語名1-2の生成処理2が実行される。
3. 上記 2.の生成処理で生成された値を入力値として目的語名1-3の生成処理2が実行される。
4. 上記 3. の値が、目的語名1-2の値（プロパティ値）となる。

生成処理は、rdf-configでは、以下の処理を提供している。

| 処理名       | 処理内容 |
|--------------|------------------------------------------------------------------------------------------------------------------------------------------------------------|
| append       | `append(str)`<br/>値の末尾にstr追加する。 |
| capitalize   | `capitalize`<br/>値（文字列）の先頭を大文字にする。 |
| change_value | `change_value(rule1, rule2, ...)`<br/>引数に配列渡し、その配列の1番目の要素を2番目の要素に変更する。<br/>例えば `chage_value(['E', 'en'], ['J', 'ja'])`とすると、'E' は 'en' に、'J' は 'ja' に変更される。 |
| csv          | `csv(col_name)`<br/>CSVのcol_nameカラムの値を取得する。 |
| datatype     | `datatype(type)`<br/>`type`には`xsd:date`等のRDFでのデータ型を指定し、オブジェクトのリテラル値がそのデータ型となるようにする。 |
| delete       | `delete(pattern)`<br/>`pattern`にマッチする部分を削除する。`pattern`には文字列または正規表現を指定する。 |
| downcase     | `downcase`<br/>文字列を全て小文字に変換する。 |
| join         | `join(str1, str2, ..., strN, sep)`<br/>`str1`から`strN`を文字列`sep`を間に挟んで連結する。 |
| json         | `json(key)`<br/>JSONから値を取得する。JSONが階層構造になっている場合、`key1.key2.key3`のように、たどるキー名をドットでつなげた値を`key`に指定する。 |
| lang         | `lang(lang_tag)`<br/>オブジェクトのリテラル値に対して、RDFの言語タグ（"ja"や"en"等）を設定する。 |
| prepend      | `prepend(str)`<br/>値の先頭に引数で指定された文字列を追加する。 |
| replace      | `replace(pattern, replace)`<br/>`pattern`にマッチする部分を`replace`で置き換える。<br/>`pattern`には置き換える文字列か正規表現を指定し、文字列を指定した場合は全く同じ文字列にだけマッチする。 |
| source       | `source(filepath)`<br/>変換対象とするファイルのパスを指定する。 |
| skip         | `skip(str1, str2, ...)`<br/>引数に任意個の文字列を指定し、処理対象の値が引数で指定された文字列の場合、その値が目的語となるトリプルを生成しない。 |
| split        | `split(sep)`<br/>値を`sep`で分割する。 |
| to_bool      | `to_bool`<br/>値を真偽値に変換する。 |
| to_float     | `to_float`<br/>値を小数に変換する。 |
| to_int       | `to_int`<br/>値を整数に変換する。 |
| tsv          | `tsv(col_name)`<br/>TSVのcol_nameカラムの値を取得する。 |
| upcase       | `upcase`<br/>文字列を全て大文字に変換する。 |
| xml          | `xml(xpath)`<br/>XMLの`xpath`にマッチする最初の要素の値を取得する。 |

上記の処理以外の処理を実行したい場合は、独自の処理を追加できる。  
処理の実体はRubyのメソッドであり、処理を記述したRubyファイルを`lib/rdf-config/convert/macros`配下に保存する。  
その際、ファイル名は`処理名.rb`とする。

### 主語の生成ルール
`convert.yaml`のトップレベルのキーに`model.yaml`での主語名を記述し、その主語のリソースURIを生成するルールを`subject`というキーに設定する。  
以下は、主語に対する`convert.yaml`の記述例である。

```yaml
MySubject:
  - source("/path/to/csv_file.csv")
  - subject: 
    - csv("id_column")
    - prepend("http://example.org/my_subject/")
```

この場合、以下のように`MySubject`の値が生成される。
1. 変換元のCSVファイルを`/path/to/csv_file.csv`に設定する。
2. `/path/to/csv_file.csv`ファイルの`id_column`カラムの値を取得する。
3. 上記で取得した値の先頭に http://example.org/my_subject/ を追加（prepend）する。

例えば `id_column`カラムの値が 1 の場合、`MySubject`の値（リソースURI）は、以下のように生成される。
1. CSVの`id_column`カラムの値を取得し、それが 1 である。
2. 上記の値 1 の先頭に  http://example.org/my_subject/ を追加する。  

この結果、MySubjectのリソースURIは  
http://example.org/my_subject/1  
となる。

### 目的語の値の生成ルール
`objects`というキーに対する値に、主語に結びつく目的語のRDFにおける値（プロパティ値）を生成するルールを記述する。  
`- objects:`以下の配列要素の各キーには`model.yaml`での目的語名を記述する。

以下は、目的語に対する`convert.yaml`の記述例である。
```yaml
MySubject:
  - source("/path/to/csv_file.csv")
  - subject:
    - csv("id_column")
    - prepend("http://example.org/my_subject/")
  - objects:
    - my_label:
      - csv("label")
      - lang("ja")
    - my_date:
      - csv("date")
      - datatype("xsd:date")
```

上記の`convert.yaml`の目的語（my_label, my_date）の生成ルールは以下のように解釈することができる。
* my_labelのプロパティ値 = CSVファイルのlabelカラムの値にRDFの言語タグ"ja"が付加されたRDFリテラル値
* my_dateのプロパティ値 = CSVファイルのdateカラムの値にデータ型"xsd:date"が付加されたRDFリテラル値

#### RDFの言語タグ、データ型の付与
上記の例では、`convert.yaml`にRDFの言語タグやデータ型を付与する処理を記述しているが、
`model.yaml`のオブジェクトの例に言語タグやデータ型が付与されている場合は、それらを参照して
プロパティ値の言語タグやデータ型を判断するため、`convert.yaml`で言語タグやデータ型の付与の処理を記述する必要はない。

例えば `model.yaml`で以下のように、目的語の例に言語タグやデータ型が付与されているとする。  
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
  - subject:
    - csv("id_column")
    - prepend("http://example.org/my_subject/")
  - objects:
    - my_label: csv("label")
    - my_date: csv("date")
```

#### RDFのプロパティ値のURI、リテラルの判別
`convert.yaml`の設定内容に従って生成されたRDFプロパティ値がURIになるか、リテラルになるかどうかは、
`model.yaml`での目的語の値の例によって決まる。

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
  - subject:
    - csv("id_column")
    - prepend("http://example.org/my_subject/")
  - objects:
    - uniprot:
      - csv("uniprot_id")
      - prepend("http://identifiers.org/uniprot/")
```

上記の`model.yaml`で、目的語`uniprot`の値の例がRDFのURIの形式になっているため、
`convert.yaml`に従って生成されたRDFトリプルの`uniprot`のプロパティ値もURIになる。

### 変数の使用
`convert.yaml`では、変数に値をセットし、それを別の場所で参照することができる。  
変数を値にセットするには、キーに変数名を記述し、そのキーに対応する値の部分に、変数の値を生成するルールを記述する。

```YAML
主語名:
  - source("/path/to/file.csv")
  - $var1: 変数$var1の生成処理
  - subject:
    # ... 主語の生成ルール
  - objects:
    - $var2:
      - 変数$var2の生成処理2-1
      - 変数$var2の生成処理2-2
    - 目的語名:
      - 目的語の処理1
      - 目的語の処理2
    # ...
```

上記のようにキーが`$`で始まっている場合、そのキー名は`convert.yaml`内で使用できる変数とみなされる。  
`$`で始まるキーに対応する生成処理を行った結果が変数の値としてセットされ、
`convert.yaml`内の別の場所から変数の値を参照（利用）することができる。

例えば、上記の`convert.yaml`では`$var2`にセットされた値を`convert.yaml`内の生成処理の部分で参照（利用）することができる。  
具体的には、変数の値を参照（利用）するには以下の2つの方法がある。
1. 生成処理の部分に変数名を埋め込んだ文字列を指定する。<br/>⇒ 例えば、生成処理の部分に "foo/$var2" と指定され、`$var2`の値が my_valとすると`$var2`の値が展開された "foo/my_val" が生成処理の結果となる。
2. 生成処理の引数に変数名を与える。<br/>⇒ 変数名の値を引数として、処理が実行される。

以下は、変数を使用する例である。

TSVファイル（`person.tsv`）

| person_id | first_name | last_name | lang |
|-----------|------------|-----------|------|
| 1         | 一郎       | 鈴木      | ja   |
| 1         | Ichiro     | SUZUKI    | en   |

`model.yaml`
```yaml
- Person <http://example.org/ontology/person/1>:
  - a: foaf:Person
  - dct:identifier:
    - person_id: 1
  - foaf:name:
    - name: YAMADA Taro
```

`convert.yaml`
```yaml
Person:
  - source("/path/to/person.tsv")
  - $id: tsv("person_id")
  - subject:
    - "http://example.org/ontology/person/$id"
  - objects:
    - person_id: $id
    - name:
      - $first_name: tsv("first_name")
      - $last_name: tsv("last_name")
      - $lang: tsv("lang")
      - "$last_name $first_name" # 文字列に変数を埋め込む例
      - lang($lang) # 処理の引数に変数を与える例
```

以下のように、リソースURIとプロパティ値が生成される。
1. 主語`Person`のリソースURIの生成
   1. 変換元のTSVファイルのパスを/path/to/person.tsvとする。
   2. TSVファイルの`person_id`カラムの値を取得し、それを変数`$id`にセットする。
   3. `Person`のリソース値を "http://example.org/ontology/person/$id" とする。<br />⇒ `$id`の値が1にセットされているため、`$id`が1に展開され、"http://example.org/ontology/person/1" となる。
2. 目的語`person_id`のプロパティ値の生成<br />⇒ `$id`が1なので`person_id`のプロパティ値は 1 となる。
3. 目的語`name`のプロパティ値の生成
   1. TSVファイルのfirst_nameカラムの値を変数`$first_name`にセットする。
   2. TSVファイルのlast_nameカラムの値を変数`$last_name`にセットする。
   3. TSVファイルのlangカラムの値を変数`$lang`にセットする。
   4. `name`のプロパティ値を "$last_name $first_name" とする。<br />⇒ `$last_name`と`$first_name`の値が展開され "鈴木 一郎" となる。
   5. `$lang`の値が "ja" なので、`name`のプロパティ値に言語タグ "ja" が設定され、"鈴木 一郎"@ja となる。

上記の結果、以下のようなRDFが生成される。
```
@prefix dct: <http://purl.org/dc/terms/> .
@prefix foaf: <http://xmlns.com/foaf/0.1/> .
@prefix rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#> .
@prefix xsd: <http://www.w3.org/2001/XMLSchema#> .

<http://example.org/ontology/person/1> a foaf:Person;
  dct:identifier 1;
  foaf:name "鈴木 一郎"@ja,
    "SUZUKI Ichiro"@en .
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

