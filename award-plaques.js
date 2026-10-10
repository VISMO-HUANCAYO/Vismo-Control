(function(){
'use strict';
const themes={wood:{name:'Madera clásica',panel:'#5b3825',ink:'#f4dfab'},black:{name:'Negro y dorado',panel:'#111511',ink:'#ead49a'},gold:{name:'Dorado y madera',panel:'#e5ce91',ink:'#211b14'}};
function periodLabel(kind,period){if(kind==='year')return String(period);if(!/^\d{4}-\d{2}$/.test(period))return String(period);return new Date(period+'-15T12:00:00Z').toLocaleDateString('es-PE',{month:'long',year:'numeric',timeZone:'UTC'});}
async function draw(entry,kind,period,theme){
const canvas=document.createElement('canvas');canvas.width=1200;canvas.height=1500;const ctx=canvas.getContext('2d'),palette=themes[theme]||themes.black;
const wood=ctx.createLinearGradient(0,0,1200,1500);wood.addColorStop(0,'#75503a');wood.addColorStop(.45,'#382117');wood.addColorStop(1,'#79543c');ctx.fillStyle=wood;ctx.fillRect(0,0,1200,1500);
for(let i=0;i<150;i++){ctx.strokeStyle=i%2?'rgba(236,180,120,.12)':'rgba(20,8,3,.16)';ctx.lineWidth=1+i%3;ctx.beginPath();const x=i*8;ctx.moveTo(x,0);ctx.bezierCurveTo(x+12,500,x-10,1000,x+4,1500);ctx.stroke();}
ctx.strokeStyle='#9b7355';ctx.lineWidth=14;ctx.strokeRect(22,22,1156,1456);ctx.strokeStyle='#291a12';ctx.lineWidth=12;ctx.strokeRect(58,58,1084,1384);
ctx.fillStyle=palette.panel;ctx.fillRect(90,90,1020,1320);if(theme==='gold'){const gold=ctx.createLinearGradient(90,90,1110,1410);gold.addColorStop(0,'#f5e7b7');gold.addColorStop(.5,'#ceac62');gold.addColorStop(1,'#efdfaa');ctx.fillStyle=gold;ctx.fillRect(90,90,1020,1320);}
ctx.strokeStyle=theme==='gold'?'#292015':'#c9aa65';ctx.lineWidth=8;ctx.strokeRect(114,114,972,1272);
const logo=new Image();logo.src=theme==='gold'?'./logo-vismo-personal.png':'./logo-vismo-blanco.png';await logo.decode();const logoWidth=260,logoHeight=logoWidth*logo.height/logo.width,logoStamp=document.createElement("canvas");logoStamp.width=logoWidth;logoStamp.height=Math.ceil(logoHeight);const stamp=logoStamp.getContext("2d");stamp.drawImage(logo,0,0,logoWidth,logoHeight);stamp.globalCompositeOperation="source-in";stamp.fillStyle=palette.ink;stamp.fillRect(0,0,logoWidth,logoHeight);ctx.drawImage(logoStamp,600-logoWidth/2,155,logoWidth,logoHeight);
ctx.textAlign='center';ctx.fillStyle=palette.ink;
function lines(text,size,width){ctx.font=size+'px Georgia';let result=[],line='';for(const word of String(text||'').split(/\s+/)){const candidate=line?line+' '+word:word;if(line&&ctx.measureText(candidate).width>width){result.push(line);line=word}else line=candidate;}if(line)result.push(line);return result;}
function text(value,y,size,maxWidth,maxHeight,bold){let rows;do{rows=lines(value,size,maxWidth);if(rows.length*size*1.35<=maxHeight)break;size--;}while(size>14);ctx.font=(bold?'bold ':'')+size+'px Georgia';rows.forEach((line,i)=>ctx.fillText(line,600,y+i*size*1.35,maxWidth));return rows.length*size*1.35;}
text(kind==='year'?'TRABAJADOR DEL AÑO':'TRABAJADOR DEL MES',335,47,860,135,true);text(periodLabel(kind,period),440,34,860,65,false);
ctx.font='italic 35px Georgia';ctx.fillText('Reconocimiento otorgado a',600,545);
text(entry.name,625,58,840,165,true);
ctx.strokeStyle=palette.ink;ctx.lineWidth=2;ctx.beginPath();ctx.moveTo(245,830);ctx.lineTo(530,830);ctx.moveTo(670,830);ctx.lineTo(955,830);ctx.stroke();ctx.font='38px Georgia';ctx.fillText('✦',600,843);
text(entry.message||'Por tu compromiso, dedicación y valioso aporte al equipo VISMO.',915,33,830,265,false);
if(entry.virtues)text(entry.virtues,1230,26,830,65,true);
ctx.font='bold 30px Georgia';ctx.fillText('VISMO',600,1320);ctx.font='20px Georgia';ctx.fillText('Visión y modernidad para vivir mejor',600,1355);
return canvas;
}
function Plaque({react:React,entry,kind,period}){const[open,setOpen]=React.useState(false),[theme,setTheme]=React.useState('black'),[preview,setPreview]=React.useState(''),[error,setError]=React.useState(''),[busy,setBusy]=React.useState(false);
React.useEffect(()=>{if(!open)return;let active=true;setPreview('');setError('');draw(entry,kind,period,theme).then(canvas=>{if(active)setPreview(canvas.toDataURL('image/png'))}).catch(err=>{if(active)setError(err.message)});return()=>{active=false}},[open,theme,entry.name,entry.message,entry.virtues,kind,period]);
async function download(){setBusy(true);setError('');try{const canvas=await draw(entry,kind,period,theme);const blob=await new Promise((resolve,reject)=>canvas.toBlob(value=>value?resolve(value):reject(Error('No se pudo generar la placa.')),'image/png'));const url=URL.createObjectURL(blob),link=document.createElement('a');link.href=url;link.download='VISMO-'+kind+'-'+period+'-'+String(entry.name||'trabajador').replace(/[^\p{L}\p{N}]+/gu,'-')+'.png';link.click();setTimeout(()=>URL.revokeObjectURL(url),60000)}catch(err){setError(err.message)}finally{setBusy(false)}}
return React.createElement('div',{className:'vismo-plaque'},React.createElement('button',{type:'button',onClick:()=>setOpen(!open)},open?'Cerrar placa':'Mi placa de reconocimiento'),open&&React.createElement(React.Fragment,null,React.createElement('label',null,'Diseño de la placa',React.createElement('select',{value:theme,onChange:event=>setTheme(event.target.value)},Object.entries(themes).map(([value,item])=>React.createElement('option',{key:value,value},item.name)))),preview?React.createElement('img',{src:preview,alt:'Placa de reconocimiento de '+entry.name,style:{display:'block',width:'100%',maxWidth:360,height:'auto',margin:'16px auto'}}):!error&&React.createElement('p',{role:'status'},'Preparando placa…'),React.createElement('button',{type:'button',className:'primary',disabled:busy||!preview,onClick:download},busy?'Generando…':'Descargar mi placa · PNG'),error&&React.createElement('p',{role:'alert'},error)));
}
window.VismoAwardPlaque=Plaque;
})();
