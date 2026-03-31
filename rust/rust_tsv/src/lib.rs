use magnus::{
    block::Proc,
    function,
    prelude::*,
    Error,
    RArray,
    Ruby,
    Value,
};

use std::fs::File;

fn each_batch(ruby: &Ruby, path: String, headers: bool, batch_size: usize) -> Result<(), Error> {
    let proc: Proc = ruby.block_proc()?;

    let file = File::open(&path).map_err(|e| {
        Error::new(
            ruby.exception_runtime_error(),
            format!("Failed to open {}: {}", path, e),
        )
    })?;

    let mut rdr = csv::ReaderBuilder::new()
        .delimiter(b'\t')
        .has_headers(headers)
        .flexible(true)
        .from_reader(file);

    let header_array: RArray = if headers {
        let hdrs = rdr.headers().map_err(|e| {
            Error::new(
                ruby.exception_runtime_error(),
                format!("Failed to read headers: {}", e),
            )
        })?;

        let ary = ruby.ary_new_capa(hdrs.len());
        for h in hdrs.iter() {
            ary.push(h.to_string())?;
        }
        ary
    } else {
        ruby.ary_new()
    };

    let mut batch: RArray = ruby.ary_new_capa(batch_size);

    for result in rdr.records() {
        let record = result.map_err(|e| {
            Error::new(
                ruby.exception_runtime_error(),
                format!("TSV parse error: {}", e),
            )
        })?;

        let row: RArray = ruby.ary_new_capa(record.len());
        for field in record.iter() {
            row.push(field.to_string())?;
        }

        batch.push(row)?;

        if batch.len() >= batch_size {
            let _: Value = proc.call((header_array.as_value(), batch.as_value()))?;
            batch = ruby.ary_new_capa(batch_size);
        }
    }

    if batch.len() > 0 {
        let _: Value = proc.call((header_array.as_value(), batch.as_value()))?;
    }

    Ok(())
}

#[magnus::init]
fn init(ruby: &Ruby) -> Result<(), Error> {
    let module = ruby.define_module("RustTsv")?;
    module.define_singleton_method("each_batch", function!(each_batch, 3))?;
    Ok(())
}
