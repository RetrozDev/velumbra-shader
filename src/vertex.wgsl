override waving_plants: bool = true;
override water_waves: bool = true;

fn wind_sway(world: vec3<f32>, t: f32) -> vec3<f32> {
    let gust = 0.6 + 0.4 * sin(t * 0.35 + world.x * 0.02 + world.z * 0.015);
    let a = sin(t * 1.7 + world.x * 0.9 + world.z * 0.4 + world.y * 0.3);
    let b = sin(t * 2.3 + world.z * 0.8 - world.x * 0.3);
    return vec3<f32>(a, b * 0.3, b) * gust;
}

fn vertex(input: VertexInput) -> vec3<f32> {
    var p = input.position;
    let world = p + frame.camera_position;
    let t = frame.time;

    if waving_plants {
        let wind = (1.0 + frame.rain * 0.8 + frame.thunder * 0.8) * smoothstep(0.2, 0.6, input.light.y);
        var amount = 0.0;
        if input.material == MAT_LEAVES {
            amount = 0.035;
        } else if input.material == MAT_PLANT {
            amount = select(0.0, 0.11, input.uv.y < 0.5);
        } else if input.material == MAT_TALL_LOWER {
            amount = select(0.0, 0.07, input.uv.y < 0.5);
        } else if input.material == MAT_TALL_UPPER {
            amount = select(0.07, 0.14, input.uv.y < 0.5);
        }
        p += wind_sway(world, t) * amount * wind;
    }

    if water_waves && input.material == MAT_WATER && input.fluid == 1u && input.face == 1u {
        p.y += wave_field(world.xz, t).x * 0.045 - 0.03;
    }
    return p;
}
