"use strict";
const thumbs=[...document.querySelectorAll("[data-shot]")];
const mainImage=document.getElementById("main-shot"), fullLink=document.getElementById("full-shot"), caption=document.getElementById("shot-caption");
const viewer=document.getElementById("screenshot-viewer"), canvas=viewer.querySelector(".viewer-canvas"), sizeButton=document.getElementById("viewer-size");
let selected=0;
function select(index){selected=(index+thumbs.length)%thumbs.length;const chosen=thumbs[selected];thumbs.forEach((b,i)=>{b.classList.toggle("active",i===selected);b.setAttribute("aria-pressed",String(i===selected))});const path="media/"+chosen.dataset.shot;mainImage.src=path;mainImage.alt=chosen.dataset.alt;fullLink.href=path;caption.textContent=chosen.dataset.caption;if(viewer.open)updateViewer()}
function updateViewer(){const picture=new Image();picture.src=mainImage.getAttribute("src");picture.alt=mainImage.alt;canvas.replaceChildren(picture);canvas.scrollTop=0;canvas.scrollLeft=0;document.getElementById("viewer-caption").textContent=caption.textContent;document.getElementById("viewer-original").href=picture.src}
function openViewer(event){if(event)event.preventDefault();if(!viewer.open){viewer.showModal();document.body.style.overflow="hidden"}updateViewer()}
thumbs.forEach((button,index)=>button.addEventListener("click",()=>select(index)));
fullLink.addEventListener("click",openViewer);document.getElementById("expand-shot").addEventListener("click",openViewer);
document.getElementById("viewer-close").addEventListener("click",()=>viewer.close());
viewer.addEventListener("close",()=>{document.body.style.overflow="";document.getElementById("expand-shot").focus()});
sizeButton.addEventListener("click",()=>{const actual=canvas.classList.toggle("actual");sizeButton.setAttribute("aria-pressed",String(actual));sizeButton.textContent=actual?"Fit to window":"Actual size (100%)"});
document.getElementById("viewer-prev").addEventListener("click",()=>select(selected-1));document.getElementById("viewer-next").addEventListener("click",()=>select(selected+1));
viewer.addEventListener("keydown",event=>{if(event.key==="ArrowLeft"){event.preventDefault();select(selected-1)}if(event.key==="ArrowRight"){event.preventDefault();select(selected+1)}});
