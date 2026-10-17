import {spawn} from 'node:child_process';
import {createInterface} from 'node:readline';
import {fileURLToPath} from 'node:url';
import path from 'node:path';
import {realpathSync} from 'node:fs';

const root=path.dirname(fileURLToPath(import.meta.url));
const string={type:'string',minLength:1};
const number={type:'number'};
const positive={type:'number',exclusiveMinimum:0};
const point={type:'array',items:number,minItems:2,maxItems:3};
const xy={type:'array',items:number,minItems:2,maxItems:2};
const object=(properties,required=Object.keys(properties))=>({type:'object',properties,required,additionalProperties:false});
const entity=(type,props,required)=>object({type:{const:type,type:'string'},...props,layer:string,linetype_scale:positive},['type',...required]);
const entities={type:'array',minItems:1,maxItems:500,items:{oneOf:[
  entity('line',{start:point,end:point},['start','end']),
  entity('circle',{center:point,radius:positive},['center','radius']),
  entity('rectangle',{origin:point,width:positive,height:positive},['origin','width','height']),
  entity('polyline',{points:{type:'array',items:xy,minItems:2,maxItems:2000},closed:{type:'boolean'}},['points']),
  entity('text',{position:point,text:{...string,maxLength:2000},height:positive},['position','text','height']),
  entity('dimension',{start:point,end:point,position:point,text_height:positive},['start','end','position']),
  entity('block',{name:string,position:point,scale:positive},['name','position']),
  // Solid fills without hatch boundaries: a zero-hole donut and a 2D SOLID (3 or 4 corners in outline order).
  entity('filled_circle',{center:xy,radius:positive},['center','radius']),
  entity('filled_polygon',{points:{type:'array',items:xy,minItems:3,maxItems:4}},['points'])
]}};
const linetypes=['CONTINUOUS','DASHED','DASHED2','DASHEDX2','HIDDEN','HIDDEN2','CENTER','CENTER2','PHANTOM','PHANTOM2','DASHDOT','DASHDOT2','DOT','DIVIDE'];
const lineweights=[0,5,9,13,15,18,20,25,30,35,40,50,53,60,70,80,90,100,106,120,140,158,200,211];
const definitions=[
 ['status','Read AutoCAD connection, open drawings, units and entity counts. No writes.',object({}),true],
 ['new_drawing','Create a separate blank millimetre drawing; preserve all existing drawings.',object({}),false],
 ['list_layers','Read active drawing layers.',object({drawing:string}),true],
 ['list_entities','Read model-space entities (or the entities inside a named block definition), handles, geometry, text style and bounding box (bbox: xmin, ymin, xmax, ymax) with an optional layer filter.',object({drawing:string,layer:string,block:string,limit:{type:'integer',minimum:1,maximum:500}},['drawing']),true],
 ['create_layer','Create a NEW layer with an optional linetype (loaded from acadiso.lin/acad.lin when missing), ACI color 1..255 and lineweight in 1/100 mm. Never modifies an existing layer.',object({drawing:string,name:string,linetype:{type:'string',enum:linetypes},color:{type:'integer',minimum:1,maximum:255},lineweight:{type:'integer',enum:lineweights}},['drawing','name']),false],
 ['draw','Create native CAD entities in one undo group. Coordinates are WCS, polylines are XY at Z=0; existing drawing units are not changed. Missing layers are created. Text uses the UNICODE-ARIAL style (arial.ttf), created if missing. Prevalidate and roll back additions on error.',object({drawing:string,entities}),false],
 ['define_block','Create a new named block at base point 0,0,0 using typed entities. Does not insert it. Never replaces an existing block.',object({drawing:string,name:string,entities}),false],
 ['zoom_extents','Fit the active drawing to the viewport.',object({drawing:string}),false],
 ['save_as',`Save a NEW DWG under ${path.join(root,'drawings')}. Never overwrite an existing file.`,object({drawing:string,path:string}),false]
];
const tools=definitions.map(([name,description,inputSchema,readOnlyHint])=>({name,description,inputSchema,annotations:{readOnlyHint,destructiveHint:false,idempotentHint:readOnlyHint,openWorldHint:false}}));

// Validate independently of the MCP client before a request can modify AutoCAD.
function validate(value,schema,where='arguments') {
 if(schema.oneOf) {if(!schema.oneOf.some(s=>{try{validate(value,s,where);return true}catch{return false}}))throw Error(`${where}: no matching entity schema`);return;}
 if(schema.const!==undefined&&value!==schema.const)throw Error(`${where}: invalid constant`);
 if(schema.enum&&!schema.enum.includes(value))throw Error(`${where}: must be one of ${schema.enum.join(', ')}`);
 if(schema.type==='object') {
  if(value===null||typeof value!=='object'||Array.isArray(value))throw Error(`${where}: expected object`);
  for(const key of schema.required??[])if(!(key in value))throw Error(`${where}.${key}: required`);
  for(const [key,v] of Object.entries(value)){if(!(key in schema.properties))throw Error(`${where}.${key}: unexpected property`);validate(v,schema.properties[key],`${where}.${key}`);}
 } else if(schema.type==='array') {
  if(!Array.isArray(value)||value.length<(schema.minItems??0)||value.length>(schema.maxItems??Infinity))throw Error(`${where}: invalid array length`);
  value.forEach((v,i)=>validate(v,schema.items,`${where}[${i}]`));
 } else if(schema.type==='number'||schema.type==='integer') {
  if(typeof value!=='number'||!Number.isFinite(value)||(schema.type==='integer'&&!Number.isInteger(value))||value<(schema.minimum??-Infinity)||value>(schema.maximum??Infinity)||(schema.exclusiveMinimum!==undefined&&value<=schema.exclusiveMinimum))throw Error(`${where}: invalid number`);
 } else if(typeof value!==schema.type||(schema.type==='string'&&(value.length<(schema.minLength??0)||value.length>(schema.maxLength??Infinity))))throw Error(`${where}: invalid ${schema.type}`);
}
export function invoke(op,args={}) {
 const tool=tools.find(t=>t.name===op); if(!tool)throw Error('Unknown tool');validate(args,tool.inputSchema);
 return new Promise((resolve,reject)=>{
  const ps=spawn(path.join(process.env.SystemRoot??'C:\\Windows','System32','WindowsPowerShell','v1.0','powershell.exe'),['-NoProfile','-NonInteractive','-STA','-File',path.join(root,'bridge.ps1')],{windowsHide:true,stdio:['pipe','pipe','pipe']});
  let stdout='',stderr='';
  // A timed-out mutation has an unknown outcome; never retry it automatically.
  const timeout=setTimeout(()=>{ps.kill();reject(Error('AutoCAD timed out; outcome is unknown. Read status/entities before any retry.'));},90000);
  ps.stdout.setEncoding('utf8');ps.stderr.setEncoding('utf8');
  ps.stdout.on('data',s=>stdout+=s);ps.stderr.on('data',s=>stderr+=s);
  ps.on('error',e=>{clearTimeout(timeout);reject(e)});
  ps.on('close',()=>{clearTimeout(timeout);try{const r=JSON.parse(stdout.trim());if(!r.ok)throw Error(r.error);resolve(r.result)}catch(e){reject(Error(e.message+(stderr?` ${stderr.slice(0,1500)}`:'')))}});
  ps.stdin.on('error',()=>{});ps.stdin.end(JSON.stringify({op,arguments:args})+'\n');
 });
}

async function dispatch(request) {
 const {id,method,params={}}=request;
 if(id===undefined)return;
 const reply=result=>process.stdout.write(JSON.stringify({jsonrpc:'2.0',id,result})+'\n');
 if(method==='initialize')return reply({protocolVersion:['2024-11-05','2025-03-26','2025-06-18','2025-11-25'].includes(params.protocolVersion)?params.protocolVersion:'2025-06-18',capabilities:{tools:{}},serverInfo:{name:'autocad-local',version:'1.0.0'},instructions:'Control AutoCAD (full version, Windows) through local COM. Read status first. Every drawing operation requires the exact active drawing name. Keep user drawings intact; use a new drawing for demos. Ask for missing engineering dimensions. Typed geometry only, no shell/LISP execution. Save only to the drawings folder, with a new filename. Do not assume standard-compliant engineering design from schematic symbols.'});
 if(method==='ping')return reply({});
 if(method==='tools/list')return reply({tools});
 if(method==='tools/call'){
  try{return reply({content:[{type:'text',text:JSON.stringify(await invoke(params.name,params.arguments??{}))}]})}
  catch(e){return reply({isError:true,content:[{type:'text',text:e.message}]})}
 }
 process.stdout.write(JSON.stringify({jsonrpc:'2.0',id,error:{code:-32601,message:'Method not found'}})+'\n');
}
// Compare real paths: a junction or shortcut folder must not stop the server from starting.
const real=p=>{try{return realpathSync(p)}catch{return path.resolve(p)}};
if(process.argv[1]&&real(process.argv[1]).toLowerCase()===real(fileURLToPath(import.meta.url)).toLowerCase()){
 let queue=Promise.resolve();
 createInterface({input:process.stdin,crlfDelay:Infinity}).on('line',line=>{
  queue=queue.then(async()=>{let request;try{request=JSON.parse(line)}catch{process.stdout.write(JSON.stringify({jsonrpc:'2.0',id:null,error:{code:-32700,message:'Parse error'}})+'\n');return;}await dispatch(request);}).catch(e=>process.stderr.write(e.message+'\n'));
 });
}
