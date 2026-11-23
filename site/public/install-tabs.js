document.querySelectorAll('[data-terminal]').forEach(terminal=>{
 const tabs=[...terminal.querySelectorAll('[role="tab"]')];
 function select(index){
   tabs.forEach((tab,i)=>{
     const panel=document.getElementById(tab.getAttribute('aria-controls'));
     tab.setAttribute('aria-selected',String(i===index));
     tab.tabIndex=i===index?0:-1;
     if(panel)panel.hidden=i!==index;
   });
 }
 tabs.forEach((tab,i)=>{
   tab.addEventListener('click',()=>select(i));
   tab.addEventListener('keydown',event=>{
     const next={ArrowLeft:(i+tabs.length-1)%tabs.length,ArrowRight:(i+1)%tabs.length,Home:0,End:tabs.length-1}[event.key];
     if(next===undefined)return;
     event.preventDefault(); select(next); tabs[next].focus();
   });
 });
 select(0);
 terminal.querySelectorAll('[data-copy-command]').forEach(button=>{
   let timer;
   button.addEventListener('click',async()=>{
     const code=button.parentElement?.querySelector('code');
     if(!code)return;
     try{
       await navigator.clipboard.writeText(code.textContent??'');
       button.textContent='Copied';
     }catch{
       const range=document.createRange();range.selectNodeContents(code);
       const selection=window.getSelection();selection?.removeAllRanges();selection?.addRange(range);
       button.textContent='Press ⌘C';
     }
     clearTimeout(timer);timer=window.setTimeout(()=>button.textContent='Copy',1500);
   });
 });
});
