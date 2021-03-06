# 設定ファイルのバリデーション
RDF-configでは、設定ファイルの正当性をチェックするため、rdf-configコマンドの実行時に、以下のようなバリデーションを行う。

## エラーチェック：以下の場合はエラーとなる
- **主語名がRDF-configの仕様を満たしているか**  
主語名はCamelCaseで、英字（大文字・小文字）のみ使用可能である。主語名がこの条件に合っていない場合はエラーとなる。

- **主語のサンプル値がURIかどうか**  
主語のサンプル値がURIとみなせない場合（prefix:local_partや <http://.... > のような形式になっていない場合）はエラーとなる。

- **主語のサンプル値の名前空間プレフィックスがprefix.yamlに設定されているかどうか**  
主語のサンプル値（URI）の名前空間プレフィックスがprefix.yamlに設定されていない場合はエラーとなる。

- **rdf:typeがURIかどうか**  
rdf:typeの値がURIとみなせない場合（prefix:local_partや <http://.... > のような形式になっていない場合）はエラーとなる。

- **rdf:typeの名前空間プレフィックスがprefix.yamlに設定されているかどうか**  
rdf:typeの値（URI）の名前空間プレフィックスがprefix.yamlに設定されていない場合はエラーとなる。

- **述語がURIかどうか**  
述語がURIとみなせない場合（prefix:local_partや <http://.... > のような形式になっていない場合）はエラーとなる。

- **述語の名前空間プレフィックスがprefix.yamlに設定されているかどうか**  
述語（URI）の名前空間プレフィックスがprefix.yamlに設定されていない場合はエラーとなる。

- **目的語名がRDF-configの仕様を満たしているか**  
目的語名はsnake_caseで、英小文字、数字、アンダースコアのみ使用可能である。目的語名がこの条件に合っていない場合はエラーとなる。

- **主語名、目的語名がmodel.yaml内でユニークかどうか**  
同一の主語名、目的語名がmodel.yaml内で複数回出現する場合はエラーとなる。

- **述語と目的語の設定方法がRDF-configの仕様を満たしているかどうか**  
RDF-configの仕様として、model.yamlは下記の構造で（順序を保存するために）ネストした配列で設定することになっている。model.yamlがこの条件を満たしていない場合はエラーとなる。
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

エラーになる例として以下のようなことが考えられる。
- 述語、目的語がYAMLの配列で設定されていない。
- 目的語のインデントがずれている（述語と目的語が同じインデントになっている）。


## ワーニングチェック：以下の場合はワーニングとなる
- **主語にrdf:typeが設定されているかどうか**  
主語に rdf:type が設定されていない場合はワーニングとなる。  
主語には rdf:type を設定することを推奨する。

- **同じプロパティ・パスを持つ目的語が複数あるかどうか**  
model.yamlを元に生成されるSPARQLで、同一のプロパティ・パスとなる目的語が複数ある場合はワーニングとなる。  
この場合、その目的語が全ての出現箇所で同じ値をもつことを前提とした SPARQL が生成されるので、必要に応じて意図した SPARQL になるよう手作業で変数名を修正する必要がある。

- **sparql.yamlのvariablesに設定されている変数名がmodel.yamlにあるかどうか**  
sparql.yamlのvariablesに設定されている主語名または目的語名がmodel.yamlで設定されていない場合はワーニングとなる。  
SPARQL生成時には、model.yamlで設定されていない主語名、目的語名は無視される。
