# SDL2 wasm emscripten practice

To run the normal demo run:

```
zig build run-demo
```



To compile for web here you first need to get [emscripten](https://emscripten.org/docs/getting_started/downloads.html)

```
git clone https://github.com/emscripten-core/emsdk.git
```



Install and activate it:

```
./emsdk/emsdk install latest

./emsdk/emsdk activate latest
```



Then you can start compiling like so:

```
zig build run-demo -Dtarget=wasm32-emscripten
```



Remember, you need to install and activate emscripten in every new shell session unless you save it to your path which I don't like to do since I don't need it on hand.



## TODO

⦁	Fetch emscripten as a dependency and run it from build like in zemscripten so I dont have to run clone the repo and install everytime.



⦁	Create more samples for 3D graphics and move all of them to their own directory.







## Resources



Pretty much everything here was copied from [zig-examples](https://github.com/castholm/zig-examples)



First got my start learning from [silbinarywolf](https://github.com/silbinarywolf/sdl-zig-demo-emscripten)'s repository



[zemscripten](https://github.com/zig-gamedev/zemscripten) provides a clean example for using emscripten

