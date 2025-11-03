# SDL2 wasm emscripten practice

To run the normal demo run:

```
zig build run-demosdl
```

When compiling for web zig will fetch emsdk automatically and build it so all you have to do is specify your target like so:

```
zig build run-demosdl -Dtarget=wasm32-emscripten
```


Remember, you need to install and activate emscripten in every new shell session unless you save it to your path which I don't like to do since I don't need it on hand.


One other example included is a nuklear-ui demo

```
zig build run-nuklear_demo
```

## NOTE

Model importing example (example/import.zig) does not compile with emscripten properly, but everything else builds fine

## TODO

*	~~Fetch emscripten as a dependency and run it from build like in zemscripten so I dont have to run clone the repo and install everytime.~~

*	~~Create more samples for 3D graphics and move all of them to their own directory.~~

*   Continue through [LearnOpenGL](https://learnopengl.com/) tutorial for examples

    * ~~Hello Triangle~~

    * ~~Transforms~~

    * ~~Textures~~

    * ~~Camera~~

    * Model Importing

    ** ~~Mesh Loading~~

    ** Material Loading

    ** Animation Importing and Playback

    ** Model Serializing
    

    * Lighting
    ** ~~Basic Lighting~~
    ** Materials
    ** Lighting Maps
    ** Light Casters
    ** Multiple Lights

    * Compute Shaders

    * Physics

    * Game Logic/Scripting



## Resources



Pretty much everything here was copied from [zig-examples](https://github.com/castholm/zig-examples)

First got my start learning from [silbinarywolf](https://github.com/silbinarywolf/sdl-zig-demo-emscripten)'s repository

[zemscripten](https://github.com/zig-gamedev/zemscripten) provides a clean example for using emscripten

[sdl3/README-emscripten](https://wiki.libsdl.org/SDL3/README-emscripten) Shows and explains how to structure your app so that it can be compiled to wasm.

Makes use of [NuklearUI](https://github.com/Immediate-Mode-UI/Nuklear) for immediate mode ui rendering.
