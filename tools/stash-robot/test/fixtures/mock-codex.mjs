import { createInterface } from 'node:readline';
const mode = process.argv[2] || 'normal';
let thread = false, turn = false, turnCount = 0;
const send = value => process.stdout.write(`${JSON.stringify(value)}\n`);
createInterface({input:process.stdin}).on('line', line => {
  const message = JSON.parse(line);
  if (!('id' in message)) return;
  if (message.method === 'initialize') return send({id:message.id,result:{userAgent:'mock'}});
  if (message.method === 'thread/start') { thread=true; send({id:message.id,result:{thread:{id:'thread-1',model:mode === 'nonimage' ? 'text-model' : 'image-model'}}}); return; }
  if (message.method === 'model/list') return send({id:message.id,result:{data:[{id:'image-model',inputModalities:['text','image']},{id:'text-model',inputModalities:['text']}]}});
  if (message.method === 'turn/start') { turn=true; turnCount++; const id=`turn-${turnCount}`; send({id:message.id,result:{turn:{id}}}); send({method:'turn/started',params:{turn:{id}}}); if (mode === 'normal') setTimeout(()=>send({id:'tool-request',method:'item/tool/call',params:{threadId:'thread-1',turnId:id,callId:'call-1',namespace:null,tool:'robot_observe',arguments:{}}}),5); return; }
  if (message.id === 'tool-request') { send({method:'item/agentMessage/delta',params:{delta:'Observed.'}}); send({method:'turn/completed',params:{turn:{id:'turn-1',status:'completed'}}}); turn=false; return; }
  if (message.method === 'turn/steer') { if (mode === 'steer-race') { send({method:'turn/completed',params:{turn:{id:'turn-1',status:'completed'}}}); return send({id:message.id,error:{code:-32602,message:'No active turn on thread'}}); } return send({id:message.id,result:{turnId:'turn-1'}}); }
  if (message.method === 'turn/interrupt') { turn=false; return send({id:message.id,result:{}}); }
  if (message.method === 'account/read') return send({id:message.id,result:{account:{type:'chatgpt'}}});
  send({id:message.id,error:{code:-32601,message:`unknown ${message.method}`}});
});
