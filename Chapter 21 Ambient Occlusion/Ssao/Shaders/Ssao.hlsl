cbuffer cbSsao : register(b0)
{
    float4x4 gProj;
    float4x4 gInvProj;
    float4x4 gProjTex;
	float4   gOffsetVectors[14];

    // For SsaoBlur.hlsl
    float4 gBlurWeights[3];

    float2 gInvRenderTargetSize;

    // Coordinates given in view space.
	// 观察空间中的各坐标
    float    gOcclusionRadius;
    float    gOcclusionFadeStart;
    float    gOcclusionFadeEnd;
    float    gSurfaceEpsilon;
};

cbuffer cbRootConstants : register(b1)
{
    bool gHorizontalBlur;
};
 
// Nonnumeric values cannot be added to a cbuffer.
// 非数值数据无法添加到常量缓冲区
Texture2D gNormalMap    : register(t0);
Texture2D gDepthMap     : register(t1);
Texture2D gRandomVecMap : register(t2);

SamplerState gsamPointClamp : register(s0);
SamplerState gsamLinearClamp : register(s1);
SamplerState gsamDepthMap : register(s2);
SamplerState gsamLinearWrap : register(s3);

static const int gSampleCount = 14;
 
// 屏幕缓冲区角点的uv
static const float2 gTexCoords[6] =
{
    float2(0.0f, 1.0f),
    float2(0.0f, 0.0f),
    float2(1.0f, 0.0f),
    float2(0.0f, 1.0f),
    float2(1.0f, 0.0f),
    float2(1.0f, 1.0f)
};
 
struct VertexOut
{
    float4 PosH : SV_POSITION;
    float3 PosV : POSITION; // 观察空间,点在近平面投影的坐标
	float2 TexC : TEXCOORD0;
};

VertexOut VS(uint vid : SV_VertexID)
{
    VertexOut vout;

    vout.TexC = gTexCoords[vid];

    // Quad covering screen in NDC space.
	// 将屏幕上的全屏四边形uv变换至NDC空间坐标
    vout.PosH = float4(2.0f*vout.TexC.x - 1.0f, 1.0f - 2.0f*vout.TexC.y, 0.0f, 1.0f);
 
    // Transform quad corners to view space near plane.
	// 将四边形的角点变换至观察空间中的近平面上
    float4 ph = mul(vout.PosH, gInvProj);
    vout.PosV = ph.xyz / ph.w;

    return vout;
}

// 获取样点p被点q遮挡程度
float OcclusionFunction(float distZ)
{
	// 如果depth(q)位于depth(p)之后(超出半球范围),则点q无法遮挡点p
	// 如果depth(q)与depth(p)距离过近,也认为点q不能遮挡点p
	// 只有点q位于点p之前,并根据用户定义的Epsilon值才能确定点q对点p的遮蔽程度
	
	float occlusion = 0.0f;
	if(distZ > gSurfaceEpsilon)
	{
		float fadeLength = gOcclusionFadeEnd - gOcclusionFadeStart;
		
		// Linearly decrease occlusion from 1 to 0 as distZ goes 
		// from gOcclusionFadeStart to gOcclusionFadeEnd.	
		// 随着distZ由Start取向End,屏蔽值由1线性缩小至0
		occlusion = saturate( (gOcclusionFadeEnd-distZ)/fadeLength );
	}
	
	return occlusion;	
}

float NdcDepthToViewDepth(float z_ndc)
{
    // z_ndc = A + B/viewZ, where gProj[2,2]=A and gProj[3,2]=B.
    float viewZ = gProj[3][2] / (z_ndc - gProj[2][2]);
    return viewZ;
}
 
float4 PS(VertexOut pin) : SV_Target
{
	// p: 要计算的环境光遮蔽目标点
	// n: 点p处的法向量
	// q: 随机偏离点p的一点
	// r: 有可能遮挡点p的一点

	// 获取像素p在观察空间中的法线与z坐标
    float3 n = normalize(gNormalMap.SampleLevel(gsamPointClamp, pin.TexC, 0.0f).xyz);
	// 从深度图中获取该像素在NDC空间内的z坐标
    float pz = gDepthMap.SampleLevel(gsamDepthMap, pin.TexC, 0.0f).r;
    pz = NdcDepthToViewDepth(pz);

	// 重新构建观察空间位置
	float3 p = (pz/pin.PosV.z)*pin.PosV;
	
	// 从随机向量纹理图中提取随机向量,并将它从[0,1]映射到[-1,+1]
	// 为什么*4?
	float3 randVec = 2.0f*gRandomVecMap.SampleLevel(gsamLinearWrap, 4.0f*pin.TexC, 0.0f).rgb - 1.0f;

	float occlusionSum = 0.0f;
	
	// Sample neighboring points about p in the hemisphere oriented by n.
	// 在以p为中心的半球内,根据法线n对p周围的点进行采样
	for(int i = 0; i < gSampleCount; ++i)
	{
		// Are offset vectors are fixed and uniformly distributed (so that our offset vectors
		// do not clump in the same direction).  If we reflect them about a random vector
		// then we get a random uniform distribution of offset vectors.
		// 偏移向量都是固定且均匀分布的
		// 如果将它们关于一个随机向量进行反射,则得到的必为一组均匀分布的随机偏移量
		float3 offset = reflect(gOffsetVectors[i].xyz, randVec);
	
		// Flip offset vector if it is behind the plane defined by (p, n).
		// 如果此偏移向量位于(p,n)所定义的平面之后,就翻转(flip)该偏移向量
		// y=sign(x): x=0,y=0;x>0,y=1,x<0,y=-1
		float flip = sign( dot(offset, n) );
		
		// Sample a point near p within the occlusion radius.
		// 在遮蔽半径内采集靠近点p的点
		float3 q = p + flip * gOcclusionRadius * offset;
		
		// Project q and generate projective tex-coords.  
		// 投影点q并生成相应的投影纹理坐标
		float4 projQ = mul(float4(q, 1.0f), gProjTex);
		projQ /= projQ.w;

		// 沿着从观察点至点q的方向,寻找离观察点最近的深度值
		// 此值未必是q的深度值,因为点q只是接近于点p的任意一点,其位置可能空无一物
		// 为此,需要查看此点在深度图中的深度值
		float rz = gDepthMap.SampleLevel(gsamDepthMap, projQ.xy, 0.0f).r;
        rz = NdcDepthToViewDepth(rz);

		// 重新构建观察空间中的位置坐标r
		float3 r = (rz / q.z) * q;

		// 测试点r是否遮挡点p
		//	dot(n,normalize(r-p),度量r距离平面(p,n)前侧的距离
		//		越趋近于此平面的前侧,就给它设定越大的遮蔽权重
		//		(p,n)面上的点r没有遮挡点p
		//	如果遮蔽点r距离目标点p过远,则认为点r不会遮挡遮蔽点p
		
		float distZ = p.z - r.z;
		float dp = max(dot(n, normalize(r - p)), 0.0f);

        float occlusion = dp*OcclusionFunction(distZ);

		occlusionSum += occlusion;
	}
	
	occlusionSum /= gSampleCount;
	
	float access = 1.0f - occlusionSum;

	// 增强SSAO图的对比度,使SSAO图的效果更加明显
	return saturate(pow(access, 6.0f));
}
