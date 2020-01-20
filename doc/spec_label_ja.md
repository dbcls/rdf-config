# RDF-config specification

## models.yaml

RDF データモデルは基本的に YAML に準拠した下記の構造で（順序を保存し、重複した出現を許容するために）ネストした配列でもたせる。インデントがズレているとエラーになること（行頭にスペースとタブを混在させないようにすべき）、主語・述語がそれぞれがキーとなるため末尾に : をつけることに注意。

```
- 主語名 (主語の例):
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

主語の例、述語、目的語の例は URI (<http://...>) か CURIE/QName (prefix:local_part) で記述する。目的語の例はリテラルでも良く、どうしても必要なら例を複数指定してもよい。なお、空白ノードは [] で表す。

主語名、目的語名は、SPARQL 検索や結果を表示する際に利用する変数名なので意味がわかりやすい名前をつける。主語名は CamelCase の単語、変数名は snake_case の単語を用いることを推奨する。

### 主語

主語の URI の例を記述する。主語には rdf:type (a) を必ず指定すること。さらに rdfs:label または dct:identifier を追記することを強く推奨する。

主語が URI の場合：
```
- Entry (<http://example.org/mydb/entry/1>):
  - a: mydb:Entry  # 型が一つの場合
  - a:             # 型が複数の場合
    - mydb:Entry
    - hoge:Fuga
  - rdf:type:      # rdf:type の短縮形 a を使わないで書く場合
    - mydb:Entry
    - hoge:Fuga
  - rdfs:label:
    - label: "1"
  - dct:identifier:
    - id: 1
```

主語が CURIE/QName の場合：
```
- Entry (mydb:1):
  - a: mydb:Entry
（以下同様）
```

主語が空白ノードの場合：
```
- []:
  - a: mydb:Entry
（以下同様）
```

TODO：主語については、GraphQLでの型名（変数名）、RDFでの型（URI)、サンプル例（URI)の３つを与える必要があり、RDFでの型とサンプル例は複数になることもあり得る。

### 述語

主語にぶら下がる述語を列挙する。必要なら同じ述語を繰り返して記述しても良い。

### 目的語

目的語の例は YAML パーザが型を推定するので、文字列（特にクオートは不要）、数値、日付などはそのまま記述できる。
URI が文字列リテラルになってしまうため、<> で囲まれた文字列は特別に URI 扱いする。
CURIE/QName も文字列リテラルになってしまうが、prefixies.yaml に定義されているプレフィックスで始まる文字列は特別に CURIE/QName と解釈する。
目的語が他の RDF モデルを参照する場合は、キーにそのモデルのクラス（my:Datatype など）を、バリューに目的語の例としてインスタンス（my:instance1 など）を記述する。
このインスタンスの URI は他の RDF モデルでの主語の例と一致させること。

サンプル例を１行で記述する場合：
```
- Subject (my:subject):
  - my:predicate1:
    - string_label: This is my value
  - my:predicate2:
    - integer_value: 123
  - my:predicate3:
    - link_url: <http://example.org/sample/uri>
  - my:predicate4:
    - link_alt: my:sample123
  - my:predicate5:
    - my:Datatype: my:instance1  # 同じモデルファイル内で主語の例として使われている URI
  - rdfs:seeAlso:
    - xref: <http://example.org/sample/uri>
```

目的語の例が長い場合は YAML の記法で | を用いることでインデントした部分を複数行リテラルとして扱われる。

```
- Subject (my:subject):
  - my:predicate:
    - value: |
        long long line of
         example explanation
        in detail
```

言語タグ（"hoge"@en, "ほげ"@ja など）は下記のように指定すれば良さそう。

```
- Subject (my:subject):
  - my:predicate:
    - name: '"hoge"@en'
```

TODO: ＜変数名ラベル付きの場合、要調整＞ リテラルの^^による型指定（"123"^^xsd:string など）は下記のように指定し、目的語の例が URI ではなくリテラルの場合に型指定と解釈すれば良さそう。

```
- Subject (my:subject):
  - my:predicate5:
    - my:Datatype: my:instance1  # 同じモデルファイル内で主語の例として使われている URI
  - my:predicate:
    - xsd:integer: 123
```

