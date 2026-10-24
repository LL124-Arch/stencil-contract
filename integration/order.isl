$ion_schema_2_0
schema_header::{imports: [
  {id: "common.isl", type: PositiveQuantity, as: Quantity},
  {id: "common.isl", type: SafeId},
  {id: "common.isl", type: Title}
]}
type::{name: Order, type: struct, fields: closed::{
  id: {type: SafeId, occurs: required},
  title: {type: Title, occurs: required},
  quantity: {type: Quantity, occurs: required}
}}
