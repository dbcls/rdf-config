# RDF-config specification

## models.yaml

RDF データモデルは基本的に YAML に準拠した下記の構造で（順序を保存し、重複した出現を許容するために）ネストした配列でもたせる。インデントがズレているとエラーになること（行頭にスペースとタブを混在させないようにすべき）、主語・述語がそれぞれがキーとなるため末尾に : をつけることに注意。

```
- 主語の例:
  - 述語: 目的語の例
  - 述語: [ "目的語の例1", "目的語の例2" ]
  - 述語:
    - 目的語の例3
    - 目的語の例4
    - 目的語の例5
  - 述語:
    - []:  # 空白ノード
      - 述語: 目的語の例
    - []:
      - 述語:
        - []:  # ネストした空白ノード
          - 述語: 目的語の例
```

主語、述語、目的語は URI (<http://...>) か CURIE/QName (prefix:local_part) で記述する。目的語はリテラルでも良く、どうしても必要なら例を複数指定してもよい。なお、空白ノードは [] で表す。

### 主語

主語の URI の例を記述する。主語には rdf:type (a) および rdfs:label または dct:identifier を追記することを強く推奨する。

主語が URI の場合：
```
- <http://example.org/mydb/entry/1>:
  - a: mydb:Entry  # 型が一つの場合
  - a:             # 型が複数の場合
    - mydb:Entry
    - hoge:Fuga
  - rdf:type:      # rdf:type の短縮形 a を使わないで書く場合
    - mydb:Entry
    - hoge:Fuga
  - rdfs:label:
    - xsd:string: "1"
  - dct:identifier:
    - xsd:integer: 1
```

主語が CURIE/QName の場合：
```
- mydb:1
  - a: mydb:Entry
（以下同様）
```

主語が空白ノードの場合：
```
- []
  - a: mydb:Entry
（以下同様）
```

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
- my:subject:
  - my:predicate1: This is my value
  - my:predicate2: 123
  - my:predicate3: <http://example.org/sample/uri>
  - my:predicate4: my:sample123
  - my:predicate5:
    - my:Datatype: my:instance1  # 同じモデルファイル内で主語の例として使われている URI
  - rdfs:seeAlso:  <http://example.org/sample/uri>
```

目的語の例が長い場合は YAML の記法で | を用いることでインデントした部分を複数行リテラルとして扱われる。

```
- my:subject:
  - my:predicate: |
        long long line of
         example explanation
        in detail
```

言語タグ（"hoge"@en, "ほげ"@ja など）は下記のように指定すれば良さそう。

```
- my:subject:
  - my:predicate: '"hoge"@en'
```

リテラルの^^による型指定（"123"^^xsd:string など）は下記のように指定し、目的語の例が URI ではなくリテラルの場合に型指定と解釈すれば良さそう。

```
- my:subject:
  - my:predicate5:
    - my:Datatype: my:instance1  # 同じモデルファイル内で主語の例として使われている URI
  - my:predicate:
    - xsd:integer: 123
```

