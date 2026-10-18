const { contextBridge, ipcRenderer } = require('electron');
contextBridge.exposeInMainWorld('pet', {
  load: () => ipcRenderer.invoke('pet:load'),
  command: (name, value) => ipcRenderer.invoke('pet:command', name, value),
  onState: callback => { const listener = (_, state) => callback(state); ipcRenderer.on('pet:state', listener); return () => ipcRenderer.removeListener('pet:state', listener); },
});
