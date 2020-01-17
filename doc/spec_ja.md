# RDF-config specification

## models.yaml

RDF データモデルは基本的に YAML に準拠した下記の構造で（順序を保存し、重複した出現を許容するために）ネストした配列でもたせる。インデントがズレているとエラーになること（行頭にスペースとタブを混在させないようにすべき）、主語・述語がそれぞれがキーとなるため末尾に : をつけることに注意。

```
- 主語:
  - 述語:
    - 目的語の型: サンプル値
  - 述語:
    - 目的語の型: サンプル値
  - 述語:
    - []:  # 空白ノード
      - 述語:
        - 目的語の型: サンプル値
    - []:
      - 述語:
        - []:  # ネストした空白ノード
          - 述語:
            - 目的語の型  # サンプル値を省略する場合
          - 述語:
            - 目的語の型: サンプル値
```

主語、述語、目的語の型は URI (<http://...>) か CURIE/QName (hoge:fuga) で記述する。なお、空白ノードは [] で表す。

### 主語

主語の URI の例を記述する。主語には rdf:type (a) および rdfs:label または dct:identifier を追記するのが望ましい。

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

主語が CURIE の場合：
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

主語にぶら下がる述語を列挙する。

### 目的語

目的語は先にデータ型をキーとして書き、値としてサンプル例を記述する。サンプル例は省略可能。

サンプル例を省略する場合：
```
- my:subject:
  - my:predicate:
    - my:object_type  # 目的語の型の URI のあとの : も記述しない点に注意
```

サンプル例を１行で記述する場合：
```
- my:subject:
  - my:predicate1: "This is my value"
    - xsd:string: This is my value  # ↑とどっちがいい？
  - my:predicate2:
    - xsd:integer: 123
  - my:predicate3:
    - rdfs:Resource: <http://example.org/sample/uri>
  - my:predicate4:
    - rdfs:Resource: my:sample123
  - my:predicate5:
    - my:Datatype  # ← これが "str"^^my:Datatype なのか my:Datatype のインスタンス URI へのリンクなのか区別できない
  - rdfs:seeAlso:
    - rdfs:Resource: <http://example.org/sample/uri>
```

長いサンプル例を記述する場合：
```
- my:subject
  - my:predicate
    - my:object_type: |
        long long line of
         example explanation
        in detail
```
