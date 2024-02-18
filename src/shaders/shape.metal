#include <metal_stdlib>
using namespace metal;

struct v2f {
  float4 position [[position]];
  float3 normal;
  half3 color;
  float2 texcoord;
};

struct PhongDescriptor {
  float3 diffuse_color;
};

struct Material {
  uint materialName;
  PhongDescriptor phong;
};

struct Mesh {
  uint vertexStart;
  uint vertexCount;
};

struct Instance {
  float4x4 transform;
  float3x3 normalTransform;
  float3 color;
  device Material* material;
  device Mesh* mesh;
};

struct CameraData {
  float4x4 projection;
  float4x4 transform;
  float3x3 normalTransform;
};

struct Scene {
  CameraData camera;
  device Instance* instances;
  device Mesh* meshes;
  device Material* materials;
  device packed_float3* vertices;
  device packed_float3* normals;
};

struct SceneData {
  device Scene* sceneData [[id(0)]];
};


v2f vertex vertexMain(device const SceneData& sceneData [[buffer(0)]],
                      uint vertexId [[vertex_id]],
                      uint instanceId [[instance_id]]) {
  v2f o;
  device Scene& scene = sceneData.sceneData[0];
  device Instance& instance = scene.instances[instanceId];
  device Mesh& mesh = instance.mesh[0];


  float4 pos = float4(scene.vertices[mesh.vertexStart + vertexId], 1.0);
  pos = instance.transform * pos;
  pos = scene.camera.projection * scene.camera.transform * pos;
  o.position = pos;

  float3 normal = scene.normals[mesh.vertexStart + vertexId];
  normal = scene.camera.normalTransform * instance.normalTransform * normal;
  o.normal = normal;

  o.texcoord = float2(0.0); // vd.texcoord.xy;

  o.color = half3(instance.color);

  return o;
}

/*
v2f vertex vertexMain_old(device const VertexData *vertexData [[buffer(0)]],
                      device const InstanceData *instanceData [[buffer(1)]],
                      device const CameraData &cameraData [[buffer(2)]],
                      uint vertexId [[vertex_id]],
                      uint instanceId [[instance_id]]) {
  v2f o;

  const device VertexData &vd = vertexData[vertexId];
  float4 pos = float4(vd.position, 1.0);
  pos = instanceData[instanceId].instanceTransform * pos;
  pos = cameraData.perspectiveTransform * cameraData.worldTransform * pos;
  o.position = pos;

  float3 normal = instanceData[instanceId].instanceNormalTransform * vd.normal;
  normal = cameraData.worldNormalTransform * normal;
  o.normal = normal;

  o.texcoord = vd.texcoord.xy;

  o.color = half3(instanceData[instanceId].instanceColor.rgb);
  o.color = half3(vd.normal * 0.5 + float3(0.5));
  return o;
}
*/
half4 fragment fragmentMain(v2f in [[stage_in]],
                            texture2d<half, access::sample> tex
                            [[texture(0)]]) {
  constexpr sampler s(address::repeat, filter::linear);
  half3 texel = half3(1.0); //tex.sample(s, in.texcoord).rgb;

  // assume light coming from (front-top-right)
  float3 l = normalize(float3(-1.0, -1.0, 1.0));

  float3 n = normalize(in.normal);

  half ndotl = half(saturate(dot(-n, l)));

  half3 illum = (in.color * texel * 0.1) + (in.color * texel * ndotl);
  return half4(illum, 1.0);
}