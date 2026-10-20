(function(root,factory){var api=factory();if(typeof module==='object'&&module.exports)module.exports=api;root.BrassNavigation=api;})(typeof globalThis!=='undefined'?globalThis:this,function(){
'use strict';
function inside(x,y,p){var yes=false;for(var i=0,j=p.length-1;i<p.length;j=i++){var a=p[i],b=p[j];if((a[1]>y)!==(b[1]>y)&&x<(b[0]-a[0])*(y-a[1])/(b[1]-a[1])+a[0])yes=!yes;}return yes;}
function edgeDistance(x,y,a,b){var dx=b[0]-a[0],dy=b[1]-a[1],t=Math.max(0,Math.min(1,((x-a[0])*dx+(y-a[1])*dy)/(dx*dx+dy*dy||1)));return Math.hypot(x-a[0]-dx*t,y-a[1]-dy*t);}
function isWater(nav,x,y,clearance){clearance=Number.isFinite(clearance)?Math.max(0,clearance):10;if(!Number.isFinite(x)||!Number.isFinite(y)||x<clearance||y<clearance||x>nav.width-clearance||y>nav.height-clearance)return false;
  return !nav.islands.some(function(island){var p=island.points;if(inside(x,y,p))return true;for(var i=0;i<p.length;i++)if(edgeDistance(x,y,p[i],p[(i+1)%p.length])<=clearance)return true;return false;});
}
function clear(nav,a,b){var d=Math.hypot(b.x-a.x,b.y-a.y),n=Math.max(1,Math.ceil(d/8));for(var i=0;i<=n;i++){var t=i/n;if(!isWater(nav,a.x+(b.x-a.x)*t,a.y+(b.y-a.y)*t,nav.clearance))return false;}return true;}
function create(islands,width,height,cell){width=Number.isFinite(width)&&width>20?width:2600;height=Number.isFinite(height)&&height>20?height:1800;cell=Number.isFinite(cell)&&cell>0?Math.max(10,cell):40;
  // Keep the graph below 5,000 nodes even for unusually small requested cells.
  while(Math.ceil(width/cell)*Math.ceil(height/cell)>=5000)cell*=1.05;
  var nav={width:width,height:height,cell:cell,clearance:10,cols:Math.ceil(width/cell),rows:Math.ceil(height/cell),islands:(islands||[]).filter(function(i){return i&&Array.isArray(i.points)&&i.points.length>=3;}).map(function(i){return {points:i.points.map(function(p){return [p[0],p[1]];})};}),nodes:[],edges:[]};
  for(var y=0;y<nav.rows;y++)for(var x=0;x<nav.cols;x++){var point={x:Math.min(width-10,(x+0.5)*cell),y:Math.min(height-10,(y+0.5)*cell)};nav.nodes.push(isWater(nav,point.x,point.y)?point:null);nav.edges.push([]);}
  for(var id=0;id<nav.nodes.length;id++){if(!nav.nodes[id])continue;var cx=id%nav.cols,cy=Math.floor(id/nav.cols);
    for(var dy=-1;dy<=1;dy++)for(var dx=-1;dx<=1;dx++){if(!dx&&!dy)continue;var nx=cx+dx,ny=cy+dy;if(nx<0||ny<0||nx>=nav.cols||ny>=nav.rows)continue;var next=ny*nav.cols+nx;if(!nav.nodes[next])continue;
      if(dx&&dy&&(!nav.nodes[cy*nav.cols+nx]||!nav.nodes[ny*nav.cols+cx]))continue;
      if(clear(nav,nav.nodes[id],nav.nodes[next]))nav.edges[id].push({id:next,cost:Math.hypot(nav.nodes[id].x-nav.nodes[next].x,nav.nodes[id].y-nav.nodes[next].y)});
    }
  }return nav;
}
function connectors(nav,p){var cx=Math.floor(p.x/nav.cell),cy=Math.floor(p.y/nav.cell),out=[];for(var dy=-3;dy<=3;dy++)for(var dx=-3;dx<=3;dx++){var x=cx+dx,y=cy+dy;if(x<0||y<0||x>=nav.cols||y>=nav.rows)continue;var id=y*nav.cols+x,n=nav.nodes[id];if(n&&clear(nav,p,n))out.push({id:id,cost:Math.hypot(p.x-n.x,p.y-n.y)});}return out;}
function findPath(nav,from,to){if(!from||!to||!isWater(nav,from.x,from.y,nav.clearance)||!isWater(nav,to.x,to.y,nav.clearance))return [];
  var start={x:from.x,y:from.y},end={x:to.x,y:to.y};if(clear(nav,start,end))return [start,end];
  var begins=connectors(nav,start),ends=connectors(nav,end);if(!begins.length||!ends.length)return [];
  var goals=new Map(ends.map(function(n){return [n.id,n.cost];})),count=nav.nodes.length,g=new Float64Array(count),parents=new Int32Array(count),closed=new Uint8Array(count),heap=[];g.fill(Infinity);parents.fill(-1);
  function heuristic(id){return Math.hypot(nav.nodes[id].x-end.x,nav.nodes[id].y-end.y);}
  function push(id,f){var item={id:id,f:f},i=heap.length;heap.push(item);while(i>0){var p=(i-1)>>1;if(heap[p].f<=f)break;heap[i]=heap[p];i=p;}heap[i]=item;}
  function pop(){var top=heap[0],last=heap.pop();if(heap.length){var i=0;while(i*2+1<heap.length){var j=i*2+1;if(j+1<heap.length&&heap[j+1].f<heap[j].f)j++;if(last.f<=heap[j].f)break;heap[i]=heap[j];i=j;}heap[i]=last;}return top;}
  begins.forEach(function(n){if(n.cost<g[n.id]){g[n.id]=n.cost;push(n.id,n.cost+heuristic(n.id));}});
  var best=-1,bestCost=Infinity;while(heap.length){var item=pop(),id=item.id;if(item.f>=bestCost)break;if(closed[id])continue;closed[id]=1;if(goals.has(id)&&g[id]+goals.get(id)<bestCost){best=id;bestCost=g[id]+goals.get(id);}
    nav.edges[id].forEach(function(edge){if(closed[edge.id])return;var cost=g[id]+edge.cost;if(cost<g[edge.id]){g[edge.id]=cost;parents[edge.id]=id;push(edge.id,cost+heuristic(edge.id));}});
  }
  if(best<0)return [];var chain=[end];for(var at=best;at>=0;at=parents[at])chain.push(nav.nodes[at]);chain.push(start);chain.reverse();
  var path=[start],index=0;while(index<chain.length-1){var next=chain.length-1;while(next>index+1&&!clear(nav,chain[index],chain[next]))next--;path.push({x:chain[next].x,y:chain[next].y});index=next;}return path;
}
return {create:create,isWater:isWater,findPath:findPath};
});
